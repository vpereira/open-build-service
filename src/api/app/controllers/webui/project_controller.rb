class Webui::ProjectController < Webui::WebuiController
  require_dependency 'opensuse/validator'
  include Webui::RequestHelper
  include Webui::ProjectHelper
  include Webui::LoadBuildresults
  include Webui::ManageRelationships

  before_action :lockout_spiders, only: [:requests, :rebuild_time, :buildresults, :maintenance_incidents]

  before_action :require_login, only: [:create, :toggle_watch, :destroy, :new, :new_incident_request,
                                       :new_release_request, :new_package_branch, :new_package]

  before_action :set_project, only: [:autocomplete_repositories, :users, :subprojects,
                                     :new_package, :new_package_branch, :incident_request_dialog, :release_request_dialog,
                                     :show, :linking_projects, :add_person, :add_group, :buildresult, :delete_dialog,
                                     :destroy, :remove_path_from_target, :rebuild_time, :packages_simple,
                                     :requests, :save, :monitor, :toggle_watch, :meta,
                                     :prjconf, :edit, :edit_comment,
                                     :status, :maintained_projects,
                                     :add_maintained_project_dialog, :add_maintained_project, :remove_maintained_project,
                                     :maintenance_incidents, :unlock_dialog, :unlock, :save_person, :save_group, :remove_role,
                                     :move_path, :save_prjconf, :clear_failed_comment, :pulse]

  # TODO: check if get_by_name or set_by_name is used for save_prjconf
  before_action :set_project_by_name, only: [:save_meta, :save_prjconf]

  before_action :set_project_by_id, only: [:update]

  before_action :load_project_info, only: [:show, :packages_simple, :rebuild_time,
                                           :maintained_projects, :add_maintained_project_dialog,
                                           :add_maintained_project, :remove_maintained_project]

  before_action :load_releasetargets, only: [:show, :incident_request_dialog]

  before_action :require_maintenance_project, only: [:maintained_projects,
                                                     :add_maintained_project_dialog,
                                                     :add_maintained_project,
                                                     :remove_maintained_project]

  before_action :set_maintained_project, only: [:remove_maintained_project]

  after_action :verify_authorized, only: [:save_new, :new_incident, :save_meta]

  def index
    @show_all = (params[:show_all].to_s == 'true')
    projects = Project.all
    projects = projects.filtered_for_list unless @show_all
    @projects = projects.pluck(:name, :title)

    atype = AttribType.find_by_namespace_and_name!('OBS', 'VeryImportantProject')
    @important_projects = Project.find_by_attribute_type(atype).where('name <> ?', 'deleted').pluck(:name, :title)

    if @spider_bot
      render :list_simple, status: params[:nextstatus]
    else
      render :list, status: params[:nextstatus]
    end
  end

  def autocomplete_projects
    render json: Project.autocomplete(params[:term]).not_maintenance_incident.order(:name).pluck(:name)
  end

  def autocomplete_incidents
    render json: Project.autocomplete(params[:term]).maintenance_incident.order(:name).pluck(:name)
  end

  def autocomplete_packages
    @project = Project.find_by(name: params[:project])
    if @project
      render json: @project.packages.autocomplete(params[:term]).pluck(:name)
    else
      render json: nil
    end
  end

  def autocomplete_repositories
    render json: @project.repositories.pluck(:name)
  end

  def users
    @users = @project.users
    @groups = @project.groups
    @roles = Role.local_roles

    switch_to_webui2
  end

  def subprojects
    @subprojects = @project.subprojects.order(:name)
    @parentprojects = @project.ancestors.order(:name)
    parent = @project.parent
    @parent_name = parent.name unless parent.nil?
    @siblings = @project.siblingprojects
  end

  def pulse
    @pulse = @project.project_log_entries.page(params[:page])
  end

  def new
    @project = Project.new
    @project.name = params[:name] if params[:name]

    @show_restore_message = params[:restore_option] && Project.deleted?(params[:name])
  end

  def new_incident
    project = Project.get_by_name(params[:ns])
    authorize project, :update?
    incident = MaintenanceIncident.build_maintenance_incident(project, params[:noaccess].present?)

    if incident
      flash[:success] = "Created maintenance incident project #{incident.project.name}"
      redirect_to(action: :show, project: incident.project.name) && return
    else
      flash[:error] = 'Incident projects shall only create below maintenance projects.'
      redirect_to(action: 'show', project: params[:ns]) && return
    end
  end

  def new_package; end

  def new_package_branch
    @remote_projects = Project.where.not(remoteurl: nil).pluck(:id, :name, :title)
  end

  def incident_request_dialog
    # TODO: Currently no way to find out where to send until the project 'maintained' relationship
    #      is really used. The API will find out magically here though.
    render_dialog
  end

  def new_incident_request
    begin
      BsRequest.transaction do
        req = BsRequest.new
        req.description = params[:description]

        action = BsRequestActionMaintenanceIncident.new(source_project: params[:project])
        req.bs_request_actions << action

        req.set_add_revision
        req.save!
      end
      flash[:success] = 'Created maintenance incident request'
    rescue MaintenanceHelper::MissingAction,
           BsRequestAction::UnknownProject,
           BsRequestAction::UnknownTargetPackage => e
      flash[:error] = e.message
      redirect_back(fallback_location: { action: 'show', project: params[:project] }) && return
    end
    redirect_to action: 'show', project: params[:project]
  end

  def release_request_dialog
    render_dialog
  end

  def new_release_request
    if params[:skiprequest]
      # FIXME2.3: do it directly here, api function missing
    else
      begin
        req = nil
        BsRequest.transaction do
          req = BsRequest.new
          req.description = params[:description]

          action = BsRequestActionMaintenanceRelease.new(source_project: params[:project])
          req.bs_request_actions << action

          req.save!
        end
        flash[:success] = 'Created maintenance release request ' \
                          "<a href='#{url_for(controller: 'request', action: 'show', number: req.number)}'>#{req.number}</a>"
      rescue Patchinfo::IncompletePatchinfo,
             BsRequestActionMaintenanceRelease::ArchitectureOrderMissmatch,
             BsRequestActionMaintenanceRelease::OpenReleaseRequests,
             BsRequestActionMaintenanceRelease::RepositoryWithoutReleaseTarget,
             BsRequestActionMaintenanceRelease::RepositoryWithoutArchitecture,
             BsRequestAction::BuildNotFinished,
             BsRequestAction::VersionReleaseDiffers,
             BsRequestAction::UnknownProject,
             BsRequestAction::Errors::UnknownTargetProject,
             BsRequestAction::UnknownTargetPackage => e
        flash[:error] = e.message
        redirect_back(fallback_location: { action: 'show', project: params[:project] }) && return
      rescue APIError
        flash[:error] = 'Internal problem while release request creation'
        redirect_back(fallback_location: { action: 'show', project: params[:project] }) && return
      end
    end
    redirect_to action: 'show', project: params[:project]
  end

  def show
    @bugowners_mail = @project.bugowner_emails

    # An incident has a patchinfo if there is a package 'patchinfo' with file '_patchinfo', try to find that:
    @has_patchinfo = false
    if @packages.map { |p| p[0] }.include?('patchinfo')
      Directory.hashed(project: @project.name, package: 'patchinfo').elements('entry') do |e|
        @has_patchinfo = true if e['name'] == '_patchinfo'
      end
    end
    @comments = @project.comments
    @comment = Comment.new
    render :show, status: params[:nextstatus] if params[:nextstatus]

    # TODO: Remove the `return unless` and the flash once this should be available to all beta users on all environments
    return unless User.current && User.current.in_beta? && (Rails.env.development? || Rails.env.test?)
    flash[:notice] = "We are currently migrating the project pages to Bootstrap. It's active only on the development and test environments while this is work-in-progress."

    switch_to_webui2
  end

  def packages_simple; end

  def linking_projects
    @linking_projects = @project.linked_by_projects.pluck(:name)
    render_dialog
  end

  def add_person
    authorize @project, :update?
  end

  def add_group
    authorize @project, :update?
  end

  def buildresult
    check_ajax
    render partial: 'buildstatus', locals: { project: @project, buildresults: @project.buildresults }
  end

  def delete_dialog
    @linking_projects = @project.linked_by_projects.pluck(:name)
    render_dialog
  end

  def destroy
    authorize @project, :destroy?
    if @project.check_weak_dependencies?
      parent = @project.parent
      @project.destroy
      flash[:notice] = 'Project was successfully removed.'
      if parent
        redirect_to project_show_path(parent)
      else
        redirect_to(action: :index)
      end
    else
      redirect_to project_show_path(@project), notice: "Project can't be removed: #{@project.errors.full_messages.to_sentence}"
    end
  end

  def requests
    @requests = @project.open_requests
    @default_request_type = params[:type] if params[:type]
    @default_request_state = params[:state] if params[:state]
    switch_to_webui2
  end

  def create
    # ns means namespace / parent project
    params[:project][:name] = "#{params[:ns]}:#{params[:project][:name]}" if params[:ns]

    @project = Project.new(project_params)
    authorize(@project, :create?)

    if Project.deleted?(@project.name) && !params[:restore_option_provided]
      redirect_to(new_project_path(name: @project.name, restore_option: true))
      return
    end

    @project.relationships.build(user: User.current,
                                 role: Role.find_by_title('maintainer'))

    @project.kind = 'maintenance' if params[:maintenance_project]

    # TODO: do this with nested attributes
    if params[:access_protection]
      @project.flags.new(status: 'disable', flag: 'access')
    end

    # TODO: do this with nested attributes
    if params[:source_protection]
      @project.flags.new(status: 'disable', flag: 'sourceaccess')
    end

    # TODO: do this with nested attributes
    if params[:disable_publishing]
      @project.flags.new(status: 'disable', flag: 'publish')
    end

    if @project.valid? && @project.store
      flash[:notice] = "Project '#{@project}' was created successfully"
      redirect_to action: 'show', project: @project.name
    else
      flash[:error] = "Failed to save project '#{@project}'. #{@project.errors.full_messages.to_sentence}."
      redirect_back(fallback_location: root_path)
    end
  end

  def restore
    project = Project.new(name: params[:project])
    authorize(project, :create?)

    if Project.deleted?(project.name)
      project = Project.restore(project.name)

      flash[:notice] = "Project '#{project}' was restored successfully"
      redirect_to action: 'show', project: project.name
    else
      flash[:error] = 'Project was never deleted.'
      redirect_back(fallback_location: root_path)
    end
  end

  def update
    authorize @project, :update?
    respond_to do |format|
      if @project.update(project_params)
        format.html { redirect_to(project_show_path(@project), notice: 'Project was successfully updated.') }
      else
        flash[:error] = 'Failed to update project'
        format.html { render :edit }
      end
    end
  end

  def remove_target_request_dialog
    render_dialog
  end

  def remove_target_request
    req = nil
    begin
      BsRequest.transaction do
        req = BsRequest.new
        req.description = params[:description]

        opts = { target_project: params[:project] }
        opts[:target_repository] = params[:repository] if params[:repository]
        action = BsRequestActionDelete.new(opts)
        req.bs_request_actions << action

        req.save!
      end
      flash[:success] = "Created <a href='#{url_for(controller: 'request',
                                                    action: 'show',
                                                    number: req.number)}'>repository delete request #{req.number}</a>"
    rescue BsRequestAction::Errors::UnknownTargetProject,
           BsRequestAction::UnknownTargetPackage => e
      flash[:error] = e.message
      redirect_to(action: :index, controller: :repositories, project: params[:project]) && return
    end
    redirect_to controller: :request, action: :show, number: req.number
  end

  def remove_path_from_target
    authorize @project, :update?

    repository = @project.repositories.find(params[:repository])
    path_element = repository.path_elements.find(params[:path])
    path_element.destroy
    if @project.valid?
      @project.store
      redirect_to({ action: :index, controller: :repositories, project: @project }, success: 'Successfully removed path')
    else
      redirect_back(fallback_location: root_path, error: "Can not remove path: #{@project.errors.full_messages.to_sentence}")
    end
  end

  def move_path
    params.require(:direction)
    repository = @project.repositories.find(params[:repository])
    path_element = repository.path_elements.find(params[:path])

    if params[:direction] == 'up'
      PathElement.transaction do
        path_element.move_higher
      end
    end
    if params[:direction] == 'down'
      PathElement.transaction do
        path_element.move_lower
      end
    end

    @project.store
    redirect_to({ action: :index, controller: :repositories, project: @project }, notice: "Path moved #{params[:direction]} successfully")
  end

  def monitor
    @name_filter = params[:pkgname]
    @lastbuild_switch = params[:lastbuild]
    if params[:defaults]
      defaults = (begin
                    Integer(params[:defaults])
                  rescue ArgumentError
                    1
                  end) > 0
    else
      defaults = true
    end
    params['expansionerror'] = 1 if params['unresolvable']
    monitor_set_filter(defaults)

    find_opt = { project: @project, view: 'status', code: @status_filter,
                 arch: @arch_filter, repository: @repo_filter }
    find_opt[:lastbuild] = 1 if @lastbuild_switch.present?

    @buildresult = Buildresult.find_hashed(find_opt)
    if @buildresult.empty?
      flash[:warning] = "No build results for project '#{@project}'"
      redirect_to action: :show, project: params[:project]
      return
    end

    unless @buildresult.key?('result')
      @buildresult_unavailable = true
      return
    end

    fill_status_cache

    @localpackages = {}
    @project.packages.each do |package|
      @localpackages[package.name] = 1
    end

    @packagenames = @packagenames.flatten.uniq.sort

    ## Filter for PackageNames ####
    @packagenames.select! { |name| filter_matches?(name, @name_filter) } if @name_filter.present?

    packagename_hash = {}
    @packagenames.each { |p| packagename_hash[p.to_s] = 1 }

    # filter out repos without current packages
    @statushash.each do |repo, hash|
      hash.each do |arch, packages|
        has_packages = false
        packages.each do |p, _|
          if packagename_hash.key?(p)
            has_packages = true
            break
          end
        end
        @repohash[repo].delete(arch) unless has_packages
      end
    end
  end

  # should be in the package controller, but all the helper functions to render the result of a build are in the project
  def package_buildresult
    check_ajax
    begin
      @buildresult = Buildresult.find_hashed(project: params[:project], package: params[:package], view: 'status', lastbuild: 1)
    rescue Backend::Error # wild work around for backend bug (sends 400 for 'not found')
    end
    @repohash = {}
    @statushash = {}

    if @buildresult
      @buildresult.elements('result') do |result|
        repo = result['repository']
        arch = result['arch']

        @repohash[repo] ||= []
        @repohash[repo] << arch

        # package status cache
        @statushash[repo] ||= {}
        @statushash[repo][arch] = {}

        stathash = @statushash[repo][arch]
        result.elements('status') do |status|
          stathash[status['package']] = status
        end
      end
    end
    render layout: false
  end

  def toggle_watch
    if User.current.watches?(@project.name)
      logger.debug "Remove #{@project} from watchlist for #{User.current}"
      User.current.remove_watched_project(@project.name)
    else
      logger.debug "Add #{@project} to watchlist for #{User.current}"
      User.current.add_watched_project(@project.name)
    end

    if request.env['HTTP_REFERER']
      redirect_back(fallback_location: root_path)
    else
      redirect_to action: :show, project: @project
    end
  end

  def meta
    @meta = @project.render_xml
  end

  def save_meta
    authorize @project, :update?

    errors = []
    begin
      Suse::Validator.validate('project', params[:meta])
      request_data = Xmlhash.parse(params[:meta])

      remove_repositories = @project.get_removed_repositories(request_data)
      errors << Project.check_repositories(remove_repositories)[:error]
      errors << Project.validate_remote_permissions(request_data)[:error]
      errors << Project.validate_link_xml_attribute(request_data, @project.name)[:error]
      errors << Project.validate_maintenance_xml_attribute(request_data)[:error]
      errors << Project.validate_repository_xml_attribute(request_data, @project.name)[:error]

      errors = errors.compact

      if errors.empty?
        Project.transaction do
          errors << @project.update_from_xml(request_data)[:error]
          errors = errors.compact
          @project.store if errors.empty?
        end
      end
    rescue Suse::ValidationError => exception
      errors << exception.message
    end

    if errors.empty?
      flash.now[:success] = 'Config successfully saved!'
      render layout: false, partial: 'layouts/webui/flash', object: flash
    else
      flash.now[:error] = errors.compact.join("\n")
      render layout: false, status: 400, partial: 'layouts/webui/flash', object: flash
    end
  end

  def prjconf
    sliced_params = params.slice(:rev)
    sliced_params.permit!

    @content = @project.config.content(sliced_params.to_h)
    switch_to_webui2
    return if @content
    flash[:error] = @project.config.errors.full_messages.to_sentence
    redirect_to controller: 'project', nextstatus: 404
  end

  def save_prjconf
    authorize @project, :update?

    params[:user] = User.current.login
    sliced_params = params.slice(:user, :comment)
    sliced_params.permit!

    content = @project.config.save(sliced_params.to_h, params[:config])

    if content
      flash.now[:success] = 'Config successfully saved!'
      status = 200
    else
      flash.now[:error] = @project.config.errors.full_messages.to_sentence
      status = 400
    end
    switch_to_webui2
    namespace = switch_to_webui2? ? 'webui2' : 'webui'
    render layout: false, status: status, partial: "layouts/#{namespace}/flash", object: flash
  end

  def clear_failed_comment
    authorize @project, :update?

    packages = Package.where(project: @project, name: params[:package])
    packages.each do |package|
      package.attribs.where(attrib_type: AttribType.find_by_namespace_and_name('OBS', 'ProjectStatusPackageFailComment')).destroy_all
    end

    respond_to do |format|
      format.html { redirect_to({ action: :status, project: @project }, notice: 'Cleared comments for packages.') }
      format.js { render js: '<em>Cleared comments for packages</em>' }
    end
  end

  def edit
    authorize @project, :update?
  end

  def edit_comment_form
    check_ajax
  end

  def edit_comment
    @package = @project.find_package(params[:package])

    at = AttribType.find_by_namespace_and_name!('OBS', 'ProjectStatusPackageFailComment')
    unless User.current.can_create_attribute_in?(@package, at)
      @comment = params[:last_comment]
      @error = "Can't create attributes in #{@package}"
      return
    end

    attr = @package.attribs.where(attrib_type: at).first_or_initialize
    v = attr.values.first_or_initialize
    v.value = params[:text]
    v.position = 1
    attr.save!
    @comment = params[:text]
  end

  def status
    all_packages = 'All Packages'
    no_project = 'No Project'
    @no_project = '_none_'
    @all_projects = '_all_'
    @current_develproject = params[:filter_devel] || all_packages
    @filter = @current_develproject
    if @filter == all_packages
      @filter = @all_projects
    elsif @filter == no_project
      @filter = @no_project
    end
    @ignore_pending = params[:ignore_pending] || false
    @limit_to_fails = params[:limit_to_fails] != 'false'
    @limit_to_old = !(params[:limit_to_old].nil? || params[:limit_to_old] == 'false')
    @include_versions = !(!params[:include_versions].nil? && params[:include_versions] == 'false')
    @filter_for_user = params[:filter_for_user]

    @develprojects = {}
    ps = calc_status(params[:project])

    @packages = ps[:packages]
    @develprojects = ps[:projects].sort_by(&:downcase)
    @develprojects.insert(0, all_packages)
    @develprojects.insert(1, no_project)

    respond_to do |format|
      format.json do
        render json: ActiveSupport::JSON.encode(@packages)
      end
      format.html
    end
  end

  def maintained_projects
    @maintained_projects = @project.maintained_project_names
  end

  def add_maintained_project_dialog
    render_dialog
  end

  def add_maintained_project
    authorize @project, :update?

    maintained_project = Project.find_by(name: params[:maintained_project])
    if maintained_project
      @project.maintained_projects.create!(project: maintained_project)
      @project.store
      redirect_to({ action: 'maintained_projects', project: @project }, notice: "Added #{params[:maintained_project]} to maintenance")
    else
      # TODO: Better redirect to the project (maintained project tab), where the user actually came from
      redirect_back(fallback_location: root_path, error: "Failed to add #{params[:maintained_project]} to maintenance")
    end
  end

  def remove_maintained_project
    authorize @project, :update?
    maintained_project = MaintainedProject.find_by(project: @maintained_project)
    if maintained_project && @project.maintained_projects.destroy(maintained_project)
      @project.store
      redirect_to({ action: 'maintained_projects', project: @project }, notice: "Removed #{@maintained_project} from maintenance")
    else
      redirect_back(fallback_location: root_path, error: "Failed to remove #{@maintained_project} from maintenance")
    end
  end

  def maintenance_incidents
    @incidents = @project.maintenance_incidents
  end

  def unlock_dialog
    render_dialog
  end

  def unlock
    authorize @project, :unlock?
    if @project.unlock(params[:comment])
      redirect_to project_show_path(@project), notice: 'Successfully unlocked project'
    else
      redirect_to project_show_path(@project), notice: "Project can't be unlocked: #{@project.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_project_by_id
    @project = Project.find(params[:id])
  end

  def main_object
    @project # used by mixins
  end

  def project_params
    params.require(:project).permit(
      :name,
      :ns,
      :title,
      :description,
      :maintenance_project,
      :access_protection,
      :source_protection,
      :disable_publishing,
      :url
    )
  end

  ################################### Before filters ###################################

  def set_maintained_project
    @maintained_project = Project.find_by(name: params[:maintained_project])
    raise ActiveRecord::RecordNotFound unless @maintained_project
  end

  def load_project_info
    find_maintenance_infos
    @packages = []
    @project.packages.order_by_name.pluck(:name, :updated_at).each do |p|
      @packages << [p[0], p[1].to_i.to_s] # convert Time to epoch ts and then to string
    end
    @ipackages = @project.expand_all_packages.find_all { |ip| !@packages.map { |p| p[0] }.include?(ip[0]) }
    @linking_projects = @project.linked_by_projects.pluck(:name)

    reqs = @project.open_requests
    @requests = (reqs[:reviews] + reqs[:targets] + reqs[:incidents] + reqs[:maintenance_release]).sort.uniq

    @nr_of_problem_packages = @project.number_of_build_problems
  end

  def load_releasetargets
    @releasetargets = []
    rts = ReleaseTarget.where(repository_id: @project.repositories)
    return if rts.empty?
    Rails.logger.debug rts.inspect
    @project.repositories.each do |repository|
      release_target = repository.release_targets.first
      @releasetargets.push(release_target.repository.project.name + '/' + release_target.repository.name) if release_target
    end
  end

  def require_maintenance_project
    unless @is_maintenance_project
      redirect_back(fallback_location: { action: 'show', project: @project })
      return false
    end
    true
  end

  ################################### Helper methods ###################################

  def find_maintenance_infos
    @project.maintenance_projects.each do |pm|
      # FIXME: skip the non official ones
      @project_maintenance_project = pm.maintenance_project.name
    end

    @is_maintenance_project = @project.is_maintenance?
    if @is_maintenance_project
      @open_maintenance_incidents = @project.maintenance_incidents.pluck('projects.name').sort.uniq

      @maintained_projects = @project.maintained_project_names
    end
    @is_incident_project = @project.is_maintenance_incident?
    return unless @is_incident_project

    @open_release_requests = BsRequest.find_for(project: @project.name,
                                                states: ['new', 'review'],
                                                types: ['maintenance_release'],
                                                roles: ['source']).pluck(:number)
  end

  def valid_target_name?(name)
    name =~ /^\w[-\.\w&]*$/
  end

  def monitor_set_filter(defaults)
    @avail_status_values = Buildresult.avail_status_values
    @filter_out = ['disabled', 'excluded', 'unknown']
    @status_filter = []
    @avail_status_values.each do |s|
      id = s.delete(' ')
      if params.key?(id)
        next if params[id].to_s == '0'
      else
        next unless defaults
      end
      next if defaults && @filter_out.include?(s)
      @status_filter << s
    end

    @avail_arch_values = []
    @avail_repo_values = []

    @project.api_obj.repositories.each do |r|
      @avail_repo_values << r.name
      @avail_arch_values << r.architectures.pluck(:name)
    end
    @avail_arch_values = @avail_arch_values.flatten.uniq.sort
    @avail_repo_values = @avail_repo_values.flatten.uniq.sort

    @arch_filter = []
    @avail_arch_values.each do |s|
      archid = valid_xml_id('arch_' + s)
      @arch_filter << s if defaults || (params.key?(archid) && params[archid])
    end

    @repo_filter = []
    @avail_repo_values.each do |s|
      repoid = valid_xml_id('repo_' + s)
      @repo_filter << s if defaults || (params.key?(repoid) && params[repoid])
    end
  end

  def filter_matches?(input, filter_string)
    result = false
    filter_string.gsub!(/\s*/, '')
    filter_string.split(',').each do |filter|
      no_invert = filter.match(/(^!?)(.+)/)
      if no_invert[1] == '!'
        result = input.include?(no_invert[2]) ? result : true
      else
        result = input.include?(no_invert[2]) ? true : result
      end
    end
    result
  end

  def calc_status(project_name)
    @api_obj = ::Project.where(name: project_name).includes(:packages).first
    @status = {}

    # needed to map requests to package id
    @name2id = {}

    @prj_status = Rails.cache.fetch("prj_status-#{@api_obj}", expires_in: 5.minutes) do
      ProjectStatus::Calculator.new(@api_obj).calc_status(pure_project: true)
    end

    status_filter_packages
    status_gather_attributes
    status_gather_requests

    @packages = []
    @status.each_value do |p|
      status_check_package(p)
    end

    { packages: @packages, projects: @develprojects.keys }
  end

  def status_check_package(p)
    currentpack = {}
    pname = p.name

    currentpack['requests_from'] = []
    key = @api_obj.name + '/' + pname
    if @submits.key?(key)
      return if @ignore_pending
      currentpack['requests_from'].concat(@submits[key])
    end

    currentpack['name'] = pname
    currentpack['failedcomment'] = p.failed_comment if p.failed_comment.present?

    newest = 0

    p.fails.each do |repo, arch, time, md5|
      next if newest > time
      next if md5 != p.verifymd5
      currentpack['failedarch'] = arch
      currentpack['failedrepo'] = repo
      newest = time
      currentpack['firstfail'] = newest
    end
    return if !currentpack['firstfail'] && @limit_to_fails

    currentpack['problems'] = []
    currentpack['requests_to'] = []

    currentpack['md5'] = p.verifymd5

    check_devel_package_status(currentpack, p)
    currentpack.merge!(project_status_set_version(p))

    if p.links_to
      if currentpack['md5'] != p.links_to.verifymd5
        currentpack['problems'] << 'diff_against_link'
        currentpack['lproject'] = p.links_to.project
        currentpack['lpackage'] = p.links_to.name
      end
    end

    return unless currentpack['firstfail'] || currentpack['failedcomment'] || currentpack['upstream_version'] ||
                  !currentpack['problems'].empty? || !currentpack['requests_from'].empty? || !currentpack['requests_to'].empty?
    if @limit_to_old
      return unless currentpack['upstream_version']
    end
    @packages << currentpack
  end

  def check_devel_package_status(currentpack, p)
    dp = p.develpack
    return unless dp
    dproject = dp.project
    currentpack['develproject'] = dproject
    currentpack['develpackage'] = dp.name
    key = "#{dproject}/#{dp.name}"
    currentpack['requests_to'].concat(@submits[key]) if @submits.key?(key)

    currentpack['develmd5'] = dp.verifymd5
    currentpack['develmtime'] = dp.maxmtime

    currentpack['problems'] << "error-#{dp.error}" if dp.error

    return unless currentpack['md5'] && currentpack['develmd5'] && currentpack['md5'] != currentpack['develmd5']

    if p.declined_request
      @declined_requests[p.declined_request].bs_request_actions.each do |action|
        next unless action.source_project == dp.project && action.source_package == dp.name

        sourcerev = Rails.cache.fetch("rev-#{dp.project}-#{dp.name}-#{currentpack['md5']}") do
          Directory.hashed(project: dp.project, package: dp.name)['rev']
        end
        if sourcerev == action.source_rev
          currentpack['currently_declined'] = p.declined_request
          currentpack['problems'] << 'currently_declined'
        end
      end
    end

    return unless currentpack['currently_declined'].nil?
    return currentpack['problems'] << 'different_changes' if p.changesmd5 != dp.changesmd5
    currentpack['problems'] << 'different_sources'
  end

  def status_filter_packages
    filter_for_user = User.find_by_login!(@filter_for_user) if @filter_for_user.present?
    current_develproject = @filter || @all_projects
    @develprojects = {}
    packages_to_filter_for = nil
    if filter_for_user
      packages_to_filter_for = filter_for_user.user_relevant_packages_for_status
    end
    @prj_status.each_value do |value|
      if value.develpack
        dproject = value.develpack.project
        @develprojects[dproject] = 1
        if (current_develproject != dproject || current_develproject == @no_project) && current_develproject != @all_projects
          next
        end
      elsif @current_develproject == @no_project
        next
      end
      if filter_for_user
        if value.develpack
          next unless packages_to_filter_for.include?(value.develpack.package_id)
        else
          next unless packages_to_filter_for.include?(value.package_id)
        end
      end
      @status[value.package_id] = value
      @name2id[value.name] = value.package_id
    end
  end

  def status_gather_requests
    # we do not filter requests for project because we need devel projects too later on and as long as the
    # number of open requests is limited this is the easiest solution
    raw_requests = BsRequest.order(:number).where(state: [:new, :review, :declined]).joins(:bs_request_actions).
                   where(bs_request_actions: { type: 'submit' }).pluck('bs_requests.number', 'bs_requests.state',
                                                                       'bs_request_actions.target_project',
                                                                       'bs_request_actions.target_package')

    @declined_requests = {}
    @submits = {}
    raw_requests.each do |number, state, tproject, tpackage|
      if state == 'declined'
        next if tproject != @api_obj.name || !@name2id.key?(tpackage)
        @status[@name2id[tpackage]].declined_request = number
        @declined_requests[number] = nil
      else
        key = "#{tproject}/#{tpackage}"
        @submits[key] ||= []
        @submits[key] << number
      end
    end
    BsRequest.where(number: @declined_requests.keys).each do |r|
      @declined_requests[r.number] = r
    end
  end

  def status_gather_attributes
    project_status_attributes(@status.keys, 'OBS', 'ProjectStatusPackageFailComment') do |package, value|
      @status[package].failed_comment = value
    end

    return unless @include_versions || @limit_to_old

    project_status_attributes(@status.keys, 'openSUSE', 'UpstreamVersion') do |package, value|
      @status[package].upstream_version = value
    end
    project_status_attributes(@status.keys, 'openSUSE', 'UpstreamTarballURL') do |package, value|
      @status[package].upstream_url = value
    end
  end

  def project_status_attributes(packages, namespace, name)
    ret = {}
    at = AttribType.find_by_namespace_and_name(namespace, name)
    return unless at
    attribs = at.attribs.where(package_id: packages)
    AttribValue.where(attrib_id: attribs).joins(:attrib).pluck('attribs.package_id, value').each do |id, value|
      yield id, value
    end
    ret
  end

  def project_status_set_version(p)
    ret = {}
    ret['version'] = p.version
    if p.upstream_version
      begin
        gup = Gem::Version.new(p.version)
        guv = Gem::Version.new(p.upstream_version)
      rescue ArgumentError
        # if one of the versions can't be parsed we simply can't say
      end

      if gup && guv && gup < guv
        ret['upstream_version'] = p.upstream_version
        ret['upstream_url'] = p.upstream_url
      end
    end
    ret
  end

  def users_path
    url_for(action: :users, project: @project.name)
  end

  def add_path(action)
    url_for(action: action, project: @project.name, role: params[:role], userid: params[:userid])
  end

  def set_project_by_name
    @project = Project.get_by_name(params['project'])
  rescue Project::UnknownObjectError
    @project = nil
  end
end
