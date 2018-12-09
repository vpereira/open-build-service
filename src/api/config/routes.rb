class WebuiMatcher
  class InvalidRequestFormat < APIError
  end

  def self.matches?(request)
    request.format.to_sym != :xml
  rescue ArgumentError => e
    raise InvalidRequestFormat, e.to_s
  end
end

# here we take everything that is XML, JSON or osc ;)
class APIMatcher
  def self.matches?(request)
    format = request.format.to_sym || :xml
    format == :xml || format == :json || public_or_about_path?(request)
  end

  def self.public_or_about_path?(request)
    request.fullpath.start_with?('/public', '/about')
  end
end

OBSApi::Application.routes.draw do
  mount Peek::Railtie => '/peek'

  cons = {
    arch: %r{[^\/]*},
    binary: %r{[^\/]*},
    filename: %r{[^\/]*},
    id: %r{\d*},
    login: %r{[^\/]*},
    package: %r{[^\/]*},
    package_name: %r{[^\/]*},
    project: %r{[^\/]*},
    project_name: %r{[^\/]*},
    repository: %r{[^\/]*},
    repository_name: %r{[^\/]*},
    service: %r{\w[^\/]*},
    title: %r{[^\/]*},
    user: %r{[^\/]*},
    repository_publish_build_id: %r{[^\/]*}
  }

  constraints(WebuiMatcher) do
    root 'webui/main#index'

    controller 'webui/main' do
      get 'main/systemstatus' => :systemstatus
    end

    resources :status_messages, only: [:create, :destroy], controller: 'webui/status_messages' do
      collection do
        get 'create_status_message_dialog' => :create_status_message_dialog
        get 'destroy_status_message_dialog' => :destroy_status_message_dialog
      end
    end

    controller 'webui/feeds' do
      get 'main/news' => :news, constraints: ->(req) { req.format == :rss }, as: :news_feed
      get 'main/latest_updates' => :latest_updates, constraints: ->(req) { req.format == :rss }, as: :latest_updates_feed
      get 'project/latest_commits/:project' => :commits, defaults: { format: 'atom' }, constraints: cons, as: 'commits_feed'
      get 'user/feed/:token' => :notifications, defaults: { format: 'rss' }, as: :user_rss_notifications
    end

    resources :attribs, constraints: cons, only: [:create, :update, :destroy], controller: 'webui/attribute' do
      collection do
        get ':project(/:package)/new' => :new, constraints: cons, as: 'new'
        get ':project(/:package)/:attribute/edit' => :edit, constraints: cons, as: 'edit'
        get ':project(/:package)' => :index, constraints: cons, as: 'index', defaults: { format: 'html' }
      end
    end

    resources :image_templates, constraints: cons, only: [:index], controller: 'webui/image_templates'

    resources :download_repositories, constraints: cons, only: [:create, :update, :destroy], controller: 'webui/download_on_demand'

    controller 'webui/configuration' do
      get 'configuration' => :index
      patch 'configuration' => :update
      get 'configuration/interconnect' => :interconnect
      post 'configuration/interconnect' => :create_interconnect
    end

    controller 'webui/subscriptions' do
      get 'notifications' => :index
      put 'notifications' => :update
    end

    controller 'webui/architectures' do
      get 'architectures' => :index
      patch 'architectures/bulk_update_availability' => :bulk_update_availability, as: 'bulk_update_availability'
    end

    controller 'webui/monitor' do
      get 'monitor/' => :index
      get 'monitor/old' => :old
      get 'monitor/update_building' => :update_building
      get 'monitor/events' => :events, as: :monitor_events
    end

    defaults format: 'html' do
      controller 'webui/package' do
        get 'package/show/:project/:package' => :show, as: 'package_show', constraints: cons
        get 'package/dependency/:project/:package' => :dependency, constraints: cons
        get 'package/binary/:project/:package/:repository/:arch/:filename' => :binary, constraints: cons, as: 'package_binary'
        get 'package/binary/download/:project/:package/:repository/:arch/:filename' => :binary_download,
            constraints: cons, as: 'package_binary_download'
        get 'package/binaries/:project/:package/:repository' => :binaries, constraints: cons, as: 'package_binaries'
        get 'package/users/:project/:package' => :users, as: 'package_users', constraints: cons
        get 'package/requests/:project/:package' => :requests, as: 'package_requests', constraints: cons
        get 'package/statistics/:project/:package/:repository/:arch' => :statistics, as: 'package_statistics', constraints: cons
        get 'package/revisions/:project/:package' => :revisions, constraints: cons, as: 'package_view_revisions'
        post 'package/submit_request/:project/:package' => :submit_request, constraints: cons
        get 'package/add_person/:project/:package' => :add_person, constraints: cons, as: 'package_add_person'
        get 'package/add_group/:project/:package' => :add_group, constraints: cons, as: 'package_add_group'
        get 'package/rdiff/:project/:package' => :rdiff, constraints: cons, as: 'package_rdiff'
        post 'package/save_new/:project' => :save_new, constraints: cons, as: 'save_new_package'
        post 'package/branch' => :branch, constraints: cons
        post 'package/save/:project/:package' => :save, constraints: cons, as: 'package_save'
        post 'package/remove/:project/:package' => :remove, constraints: cons
        get 'package/add_file/:project/:package' => :add_file, constraints: cons, as: 'package_add_file'
        post 'package/save_file/:project/:package' => :save_file, constraints: cons
        post 'package/remove_file/:project/:package/:filename' => :remove_file, constraints: cons
        post 'package/save_person/:project/:package' => :save_person, constraints: cons, as: 'package_save_person'
        post 'package/save_group/:project/:package' => :save_group, constraints: cons, as: 'package_save_group'
        post 'package/remove_role/:project/:package' => :remove_role, constraints: cons, as: 'package_remove_role'
        get 'package/view_file/:project/:package/(:filename)' => :view_file, constraints: cons, as: 'package_view_file'
        get 'package/live_build_log/:project/:package/:repository/:arch' => :live_build_log, constraints: cons, as: 'package_live_build_log'
        defaults format: 'js' do
          get 'package/linking_packages/:project/:package' => :linking_packages, constraints: cons, as: 'linking_packages'
          get 'package/update_build_log/:project/:package/:repository/:arch' => :update_build_log, constraints: cons, as: 'package_update_build_log'
          get 'package/submit_request_dialog/:project/:package' => :submit_request_dialog, constraints: cons, as: 'package_submit_request_dialog'
          get 'package/delete_dialog/:project/:package' => :delete_dialog, constraints: cons, as: 'package_delete_dialog'
          post 'package/trigger_rebuild/:project/:package' => :trigger_rebuild, constraints: cons, as: 'package_trigger_rebuild'
          get 'package/abort_build/:project/:package' => :abort_build, constraints: cons, as: 'package_abort_build'
          post 'package/trigger_services/:project/:package' => :trigger_services, constraints: cons, as: 'package_trigger_services'
          delete 'package/wipe_binaries/:project/:package' => :wipe_binaries, constraints: cons, as: 'package_wipe_binaries'
        end
        get 'package/devel_project/:project/:package' => :devel_project, constraints: cons, as: 'package_devel_project'
        get 'package/buildresult' => :buildresult, constraints: cons, as: 'package_buildresult'
        get 'package/rpmlint_result' => :rpmlint_result, constraints: cons, as: 'rpmlint_result'
        get 'package/rpmlint_log' => :rpmlint_log, constraints: cons
        get 'package/meta/:project/:package' => :meta, constraints: cons, as: 'package_meta'
        post 'package/save_meta/:project/:package' => :save_meta, constraints: cons, as: 'package_save_meta'
        # compat route
        get 'package/attributes/:project/:package', to: redirect('/attribs/%{project}/%{package}'), constraints: cons
        get 'package/edit/:project/:package' => :edit, constraints: cons, as: :package_edit
        # compat routes
        get 'package/repositories/:project/:package', to: redirect('/repositories/%{project}/%{package}'), constraints: cons
        get 'package/import_spec/:project/:package' => :import_spec, constraints: cons
        # compat route
        get 'package/files/:project/:package' => :show, constraints: cons
      end
    end

    resources :packages, only: [], param: :name do
      resource :job_history, controller: 'webui/packages/job_history', only: [] do
        get '/:project/:repository/:arch' => :index, as: :index, constraints: cons
      end

      resource :build_reason, controller: 'webui/packages/build_reason', only: [] do
        get '/:project/:repository/:arch' => :index, as: :index, constraints: cons
      end
    end

    controller 'webui/patchinfo' do
      post 'patchinfo/new_patchinfo' => :new_patchinfo
      post 'patchinfo/updatepatchinfo' => :updatepatchinfo
      get 'patchinfo/edit_patchinfo' => :edit_patchinfo
      get 'patchinfo/show/:project/:package' => :show, as: 'patchinfo_show', constraints: cons, defaults: { format: 'html' }
      post 'patchinfo/save/:project/:package' => :save, constraints: cons, as: :patchinfo_save
      post 'patchinfo/remove' => :remove
      get 'patchinfo/new_tracker' => :new_tracker
      get 'patchinfo/delete_dialog' => :delete_dialog
    end

    controller 'webui/repositories' do
      get 'repositories/:project(/:package)' => :index, constraints: cons, as: 'repositories', defaults: { format: 'html' }
      get 'project/repositories/:project' => :index, constraints: cons, as: 'project_repositories'
      get 'project/add_repository/:project' => :new, constraints: cons
      get 'project/add_repository_from_default_list/:project' => :distributions, constraints: cons, as: :repositories_distributions
      post 'project/save_repository' => :create
      post 'project/update_target/:project' => :update, constraints: cons
      get 'project/repository_state/:project/:repository' => :state, constraints: cons, as: 'project_repository_state'
      post 'project/remove_target' => :destroy, as: 'destroy_repository'
      post 'project/create_dod_repository' => :create_dod_repository, as: 'create_dod_repository'
      post 'project/create_image_repository' => :create_image_repository

      # Flags
      put 'flag/:project(/:package)' => :toggle_flag, constraints: cons, as: 'toggle_repository_flag'
      post 'flag/:project(/:package)' => :create_flag, constraints: cons, as: 'create_repository_flag'
      delete 'flag/:project(/:package)/:flag' => :remove_flag, constraints: cons, as: 'remove_repository_flag'
    end

    controller 'webui/kiwi/images' do
      get 'package/:package_id/kiwi_images/import_from_package' => :import_from_package, as: 'import_kiwi_image'
    end

    resources :kiwi_images, only: [:show, :edit, :update], controller: 'webui/kiwi/images' do
      member do
        get 'build_result' => :build_result, constraints: cons
        get 'autocomplete_binaries'
      end
    end

    scope :cloud, as: :cloud do
      resources :configuration, only: [:index], controller: 'webui/cloud/configurations'

      resources :upload, only: [:index, :create, :destroy], controller: 'webui/cloud/upload_jobs' do
        new do
          get ':project/:package/:repository/:arch/:filename', to: 'webui/cloud/upload_jobs#new', as: '', constraints: cons
        end

        resource :log, only: :show, controller: 'webui/cloud/upload_job/logs'
      end
      scope :azure, as: :azure do
        resource :configuration, only: [:show, :update, :destroy], controller: 'webui/cloud/azure/configurations'
        resource :upload, only: [:create], controller: 'webui/cloud/azure/upload_jobs' do
          new do
            get ':project/:package/:repository/:arch/:filename', to: 'webui/cloud/azure/upload_jobs#new', as: '', constraints: cons
          end
        end
      end
      scope :ec2, as: :ec2 do
        resource :configuration, only: [:show, :update], controller: 'webui/cloud/ec2/configurations'
        resource :upload, only: [:create], controller: 'webui/cloud/ec2/upload_jobs' do
          new do
            get ':project/:package/:repository/:arch/:filename', to: 'webui/cloud/ec2/upload_jobs#new', as: '', constraints: cons
          end
        end
      end
    end

    controller 'webui/projects/meta' do
      get 'project/meta/:project' => :show, constraints: cons, as: 'project_meta'
      post 'project/save_meta/:project' => :update, constraints: cons, as: :project_save_meta
    end

    controller 'webui/projects/project_configuration' do
      get 'project/prjconf/:project' => :show, constraints: cons, as: :project_config
      post 'project/save_prjconf/:project' => :update, constraints: cons, as: :save_project_config
    end

    controller 'webui/project' do
      get 'project/' => :index, as: 'projects'
      get 'project/list_public' => :index
      get 'project/list_all' => :index, show_all: true
      get 'project/list' => :index
      get 'project/autocomplete_projects' => :autocomplete_projects, as: 'autocomplete_projects'
      get 'project/autocomplete_incidents' => :autocomplete_incidents
      get 'project/autocomplete_packages' => :autocomplete_packages, as: 'autocomplete_packages'
      get 'project/autocomplete_repositories' => :autocomplete_repositories
      get 'project/users/:project' => :users, constraints: cons, as: 'project_users'
      get 'project/subprojects/:project' => :subprojects, constraints: cons, as: 'project_subprojects'
      get 'project/attributes/:project', to: redirect('/attribs/%{project}'), constraints: cons
      post 'project/new_incident' => :new_incident
      get 'project/new_package/:project' => :new_package, constraints: cons, as: 'project_new_package'
      get 'project/new_package_branch/:project' => :new_package_branch, constraints: cons, as: 'project_new_package_branch'
      get 'project/incident_request_dialog' => :incident_request_dialog
      post 'project/new_incident_request' => :new_incident_request
      get 'project/release_request_dialog' => :release_request_dialog
      post 'project/new_release_request/(:project)' => :new_release_request, constraints: cons, as: :project_new_release_request
      get 'project/show/(:project)' => :show, constraints: cons, as: 'project_show'
      get 'project/packages_simple/:project' => :packages_simple, constraints: cons
      get 'project/linking_projects/:project' => :linking_projects, constraints: cons, as: :linking_projects
      get 'project/add_person/:project' => :add_person, constraints: cons
      get 'project/add_group/:project' => :add_group, constraints: cons
      get 'project/buildresult' => :buildresult, constraints: cons, as: 'project_buildresult'
      get 'project/delete_dialog' => :delete_dialog
      get 'project/new' => :new, as: 'new_project'
      post 'project/create' => :create, constraints: cons, as: 'projects_create'
      post 'project/restore' => :restore, constraints: cons, as: 'projects_restore'
      patch 'project/update' => :update, constraints: cons
      delete 'project/destroy' => :destroy
      get 'project/packages/:project' => :packages, constraints: cons
      get 'project/requests/:project' => :requests, constraints: cons, as: 'project_requests'
      post 'project/save_path_element' => :save_path_element
      get 'project/remove_target_request_dialog' => :remove_target_request_dialog
      post 'project/remove_target_request' => :remove_target_request, as: 'project_remove_target_request'
      post 'project/remove_path_from_target' => :remove_path_from_target, as: 'remove_repository_path'
      post 'project/release_repository/:project/:repository' => :release_repository, constraints: cons
      get 'project/release_repository_dialog/:project/:repository' => :release_repository_dialog, constraints: cons
      post 'project/move_path/:project' => :move_path, as: 'move_repository_path'
      post 'project/save_person/:project' => :save_person, constraints: cons, as: 'project_save_person'
      post 'project/save_group/:project' => :save_group, constraints: cons, as: 'project_save_group'
      post 'project/remove_role/:project' => :remove_role, constraints: cons, as: 'project_remove_role'
      post 'project/remove_person/:project' => :remove_person, constraints: cons
      post 'project/remove_group/:project' => :remove_group, constraints: cons
      get 'project/monitor/(:project)' => :monitor, constraints: cons, as: 'project_monitor'
      get 'project/package_buildresult/:project' => :package_buildresult, constraints: cons
      # TODO: this should be POST (and the link AJAX)
      get 'project/toggle_watch/:project' => :toggle_watch, constraints: cons, as: 'project_toggle_watch'
      get 'project/clear_failed_comment/:project' => :clear_failed_comment, constraints: cons, as: :clear_failed_comment
      get 'project/edit/:project' => :edit, constraints: cons
      get 'project/edit_comment_form/:project' => :edit_comment_form, constraints: cons, as: :edit_comment_form
      post 'project/edit_comment/:project' => :edit_comment, constraints: cons
      get 'project/status/(:project)' => :status, constraints: cons, as: 'project_status'
      get 'project/maintained_projects/:project' => :maintained_projects, constraints: cons, as: :project_maintained_projects
      get 'project/add_maintained_project_dialog' => :add_maintained_project_dialog, constraints: cons
      post 'project/add_maintained_project' => :add_maintained_project, constraints: cons
      post 'project/remove_maintained_project/:project' => :remove_maintained_project, constraints: cons
      get 'project/maintenance_incidents/:project' => :maintenance_incidents, constraints: cons, as: :project_maintenance_incidents
      get 'project/list_incidents/:project' => :list_incidents, constraints: cons
      get 'project/unlock_dialog' => :unlock_dialog
      post 'project/unlock' => :unlock
    end

    get 'project/dashboard/:project' => 'webui/obs_factory/distributions#show', as: 'dashboard', constraints: cons
    get 'project/staging_projects/:project' => 'webui/obs_factory/staging_projects#index', as: 'staging_projects', constraints: cons
    get 'project/staging_projects/:project/:project_name' => 'webui/obs_factory/staging_projects#show', as: 'staging_project', constraints: cons

    controller 'webui/projects/rebuild_times' do
      get 'project/rebuild_time/:project/:repository/:arch' => :show, constraints: cons, as: :project_rebuild_time
      get 'project/rebuild_time_png/:project/:key' => :rebuild_time_png, constraints: cons, as: :project_rebuild_time_png
    end

    controller 'webui/projects/pulse' do
      get 'project/pulse/:project' => :show, constraints: cons, as: 'project_pulse'
      get 'project/pulse/:project/update_pulse' => :update_pulse, constraints: cons, as: 'update_pulse'
    end

    resources :projects, only: [], param: :name do
      resource :public_key, controller: 'webui/projects/public_key', only: [:show], constraints: cons do
        member do
          get 'key_dialog'
        end
      end
      resource :ssl_certificate, controller: 'webui/projects/ssl_certificate', only: [:show], constraints: cons
    end

    controller 'webui/request' do
      get 'request/add_reviewer_dialog' => :add_reviewer_dialog
      post 'request/add_reviewer' => :add_reviewer
      post 'request/modify_review' => :modify_review
      get 'request/show/:number' => :show, as: 'request_show', constraints: cons
      post 'request/sourcediff' => :sourcediff
      post 'request/changerequest' => :changerequest
      get 'request/diff/:number' => :diff
      get 'request/list_small' => :list_small, as: 'request_list_small'
      get 'request/delete_request_dialog' => :delete_request_dialog, as: 'request_delete_dialog'
      post 'request/delete_request/:project' => :delete_request, constraints: cons, as: 'delete_request'
      get 'request/add_role_request_dialog' => :add_role_request_dialog, as: 'request_add_role_dialog'
      post 'request/add_role_request/:project' => :add_role_request, constraints: cons, as: 'add_role_request'
      get 'request/set_bugowner_request_dialog' => :set_bugowner_request_dialog
      post 'request/set_bugowner_request' => :set_bugowner_request
      get 'request/change_devel_request_dialog/:project/:package' => :change_devel_request_dialog, constraints: cons, as: 'request_change_devel_dialog'
      post 'request/change_devel_request/:project/:package' => :change_devel_request, constraints: cons, as: 'change_devel_request'
      get 'request/set_incident_dialog' => :set_incident_dialog
      post 'request/set_incident' => :set_incident
    end

    controller 'webui/search' do
      match 'search' => :index, via: [:get, :post]
      get 'search/owner' => :owner
    end

    controller 'webui/user' do
      get 'users' => :index

      post 'user/register' => :register
      get 'user/register_user' => :register_user

      post 'user/save' => :save, constraints: cons
      get 'user/save_dialog' => :save_dialog

      post 'user/change_password' => :change_password
      get 'user/password_dialog' => :password_dialog

      patch 'user' => :update, as: 'user_update'
      delete 'user' => :delete, as: 'user_delete'

      get 'user/autocomplete' => :autocomplete
      get 'user/tokens' => :tokens

      get 'user/edit/:user' => :edit, constraints: cons, as: 'user_edit'

      get 'user/show/:user' => :show, constraints: cons, as: 'user_show'

      # Only here to make old /home url's work
      get 'home/' => :home, as: 'home'
      get 'home/my_work' => :home
      get 'home/list_my' => :home
      get 'home/home_project' => :home_project
    end

    controller 'webui/users/announcements' do
      post 'users/announcements/:id' => :create, as: 'user_announcements'
    end

    resources :announcements, only: :show, controller: 'webui/announcements'

    controller 'webui/session' do
      get 'session/new' => :new
      post 'session/create' => :create
      delete 'session/destroy' => :destroy
    end

    get 'user/notifications' => :index, constraints: cons, controller: 'webui/users/subscriptions'
    put 'user/notifications' => :update, constraints: cons, controller: 'webui/users/subscriptions'

    get 'user/tasks' => :index, constraints: cons, controller: 'webui/users/tasks', as: 'user_tasks'

    # Hardcoding this routes is necessary because we rely on the :user parameter
    # in check_display_user before filter. Overwriting of the parameter is not
    # possible for nested resources atm.
    controller 'webui/users/bs_requests' do
      get 'users/(:user)/requests' => :index, as: 'user_requests'
    end

    controller 'webui/groups/bs_requests' do
      get 'groups/(:title)/requests' => :index, constraints: { title: /[^\/]*/ }, as: 'group_requests'
    end

    controller 'webui/users/rss_tokens' do
      post 'users/rss_tokens' => :create, as: 'user_rss_token'
    end

    controller 'webui/groups' do
      get 'groups' => :index
      get 'group/show/:title' => :show, constraints: { title: /[^\/]*/ }, as: 'group_show'
      get 'group/new' => :new
      post 'group/create' => :create
      get 'group/edit/:title' => :edit, constraints: { title: /[^\/]*/ }, as: :group_edit_title
      post 'group/update/:title' => :update, constraints: { title: /[^\/]*/ }, as: :group_update
      get 'group/autocomplete' => :autocomplete
      delete 'group/:title/delete/:user' => :delete, constraints: { title: /[^\/]*/ }, as: :group_user_delete
    end

    resources :comments, constraints: cons, only: [:create, :destroy], controller: 'webui/comments'

    ### /apidocs
    get 'apidocs', to: redirect('/apidocs/index')
    get 'apidocs/(index)' => 'webui/apidocs#index', as: 'apidocs_index'
  end

  scope :worker, as: :worker do
    resources :status, only: [:index], controller: 'worker/status'
    resources :capability, only: [:show], param: :worker, controller: 'worker/capability'
    resources :command, only: [], controller: 'worker/command' do
      collection do
        post 'run'
      end
    end
  end

  ### /worker
  get 'worker/_status' => 'worker/status#index', as: :worker_status
  get 'build/_workerstatus' => 'worker/status#index', as: :build_workerstatus # FIXME3.0: drop this compat route
  get 'worker/:worker' => 'worker/capability#show'
  post 'worker' => 'worker/command#run'

  ### /build
  get 'build/:project/:repository/:arch/:package/_log' => 'build#logfile', constraints: cons, as: :raw_logfile
  match 'build/:project/:repository/:arch/:package/_buildinfo' => 'build#buildinfo', constraints: cons, via: [:get, :post]
  match 'build/:project/:repository/:arch/:package/_status' => 'build#index', constraints: cons, via: [:get, :post]
  match 'build/:project/:repository/:arch/:package/_history' => 'build#index', constraints: cons, via: [:get, :post]
  get 'build/:project/:repository/:arch/:package/:filename' => 'build/file#show', constraints: cons
  put 'build/:project/:repository/:arch/:package/:filename' => 'build/file#update', constraints: cons
  delete 'build/:project/:repository/:arch/:package/:filename' => 'build/file#destroy', constraints: cons
  match 'build/:project/:repository/:arch/_builddepinfo' => 'build#builddepinfo', via: [:get, :post], constraints: cons
  match 'build/:project/:repository/_buildconfig' => 'build#index', constraints: cons, via: [:get, :post]
  match 'build/:project/:repository/:arch(/:package)' => 'build#index', constraints: cons, via: [:get, :post]
  get 'build/:project/_result' => 'build#result', constraints: cons
  match 'build/:project/:repository' => 'build#index', constraints: cons, via: [:get, :post]
  match 'build/:project' => 'build#project_index', constraints: cons, via: [:get, :post, :put]
  get 'build' => 'source#index'

  ### /published

  # :arch can be also a ymp for a pattern :/
  get 'published/:project(/:repository(/:arch(/:binary)))' => 'published#index', constraints: cons
  get 'published/' => 'source#index', via: :get

  constraints(APIMatcher) do
    get '/' => 'main#index'

    resource :configuration, only: [:show, :update, :schedulers]

    resources :announcements, except: [:edit, :new]

    ### /person
    post 'person' => 'person#command'
    get 'person' => 'person#show'
    post 'person/:login/login' => 'person#login', constraints: cons # temporary hack for webui, do not use, to be removed
    get 'person/:login/token' => 'person/token#index', constraints: cons
    post 'person/:login/token' => 'person/token#create', constraints: cons
    delete 'person/:login/token/:id' => 'person/token#delete', constraints: cons

    # FIXME3.0: this is no clean namespace, a person "register" or "changepasswd" could exist ...
    #           remove these for OBS 3.0
    match 'person/register' => 'person#register', via: [:post, :put] # use /person?cmd=register POST instead
    match 'person/changepasswd' => 'person#change_my_password', via: [:post, :put] # use /person/:login?cmd=changepassword POST instead
    get 'person/:login/group' => 'person#grouplist', constraints: cons # Use /group?person=:login GET instead
    # /FIXME3.0
    match 'person/:login' => 'person#get_userinfo', constraints: cons, via: [:get]
    match 'person/:login' => 'person#put_userinfo', constraints: cons, via: [:put]
    match 'person/:login' => 'person#post_userinfo', constraints: cons, via: [:post]

    ### /group
    controller :group do
      get 'group' => :index
      get 'group/:title' => :show, constraints: cons
      delete 'group/:title' => :delete, constraints: cons
      put 'group/:title' => :update, constraints: cons
      post 'group/:title' => :command, constraints: cons
    end

    ### /service
    get 'service' => 'service#index'
    get 'service/:service' => 'service#index_service', constraints: cons

    ### /source

    get 'source/:project/:package/_tags' => 'tag#package_tags', constraints: cons
    get 'source/:project/_tags' => 'tag#project_tags', constraints: cons
    get 'source/:project/_keyinfo' => 'source/key_info#show', constraints: cons

    resources :about, only: :index

    controller :attribute_namespace do
      get 'attribute' => :index
      get 'attribute/:namespace' => :index
      # FIXME3.0: drop the POST and DELETE here
      get 'attribute/:namespace/_meta' => :show
      delete 'attribute/:namespace/_meta' => :delete
      delete 'attribute/:namespace' => :delete
      match 'attribute/:namespace/_meta' => :update, via: [:post, :put]
    end

    controller :attribute do
      get 'attribute/:namespace/:name/_meta' => :show
      delete 'attribute/:namespace/:name/_meta' => :delete
      delete 'attribute/:namespace/:name' => :delete
      match 'attribute/:namespace/:name/_meta' => :update, via: [:post, :put]
    end

    ### /architecture
    resources :architectures, only: [:index, :show, :update] # create,delete currently disabled

    ### /trigger
    post 'trigger/runservice' => 'trigger#runservice'
    post 'trigger/webhook' => 'services/webhooks#create'

    ### /issue_trackers
    get 'issue_trackers/issues_in' => 'issue_trackers#issues_in'
    resources :issue_trackers, only: [:index, :show, :create, :update, :destroy] do
      resources :issues, only: [:show] # Nested route
    end

    ### /tag

    # routes for tagging support
    #
    # get 'tag/_all' => 'tag',
    #  action: 'list_xml'
    # Get/put tags by object
    ### moved to source section

    # Get objects by tag.
    controller :tag do
      get 'tag/:tag/_projects' => :get_projects_by_tag
      get 'tag/:tag/_packages' => :get_packages_by_tag
      get 'tag/:tag/_all' => :get_objects_by_tag

      get 'tag/get_tagged_projects_by_user' => :get_tagged_projects_by_user
      get 'tag/get_tagged_packages_by_user' => :get_tagged_packages_by_user
      get 'tag/get_tags_by_user' => :get_tags_by_user
      get 'tag/tags_by_user_and_object' => :tags_by_user_and_object
      get 'tag/get_tags_by_user_and_project' => :get_tags_by_user_and_project
      get 'tag/get_tags_by_user_and_package' => :get_tags_by_user_and_package
      get 'tag/most_popular_tags' => :most_popular_tags
      get 'tag/most_recent_tags' => :most_recent_tags
      get 'tag/get_taglist' => :get_taglist
      get 'tag/project_tags' => :project_tags
      get 'tag/package_tags' => :package_tags
    end

    ### /user

    # Get objects tagged by user. (objects with tags)
    get 'user/:user/tags/_projects' => 'tag#get_tagged_projects_by_user', constraints: cons
    get 'user/:user/tags/_packages' => 'tag#get_tagged_packages_by_user', constraints: cons

    # Get tags for a certain object by user.
    match 'user/:user/tags/:project(/:package)' => 'tag#tags_by_user_and_object', constraints: cons, via: [:get, :post, :put, :delete]

    ### /statistics
    # Routes for statistics
    # ---------------------
    controller :statistics do
      # Download statistics
      #
      get 'statistics/download_counter' => :download_counter

      # Timestamps
      #
      get 'statistics/added_timestamp/:project(/:package)' => :added_timestamp, constraints: cons
      get 'statistics/updated_timestamp/:project(/:package)' => :updated_timestamp, constraints: cons

      # Ratings
      #
      get 'statistics/rating/:project(/:package)' => :rating, constraints: cons

      # Activity
      #
      get 'statistics/activity/:project(/:package)' => :activity, constraints: cons

      # Newest stats
      #
      get 'statistics/newest_stats' => :newest_stats

      get 'statistics' => :index
      get 'statistics/highest_rated' => :highest_rated
      get 'statistics/most_active_projects' => :most_active_projects
      get 'statistics/most_active_packages' => :most_active_packages
      get 'statistics/latest_added' => :latest_added
      get 'statistics/latest_updated' => :latest_updated
      get 'statistics/global_counters' => :global_counters
      get 'statistics/latest_built' => :latest_built

      get 'statistics/active_request_creators/:project' => :active_request_creators, constraints: cons
      get 'statistics/maintenance_statistics/:project' => 'statistics/maintenance_statistics#index', constraints: cons,
          as: 'maintenance_statistics'
      get 'public/statistics/maintenance_statistics/:project' => 'statistics/maintenance_statistics#index', constraints: cons
    end

    ### /status_message
    resources :status_messages, only: [:show, :index, :create, :destroy], path: 'status/messages'

    resources :status_project, only: [:show], param: :project, path: 'status/project'

    get 'status_message' => 'status_messages#index'
    get 'status/workerstatus' => 'worker/status#index'

    ### /message

    # Routes for messages
    # --------------------------
    controller :message do
      put 'message' => :update
      get 'message' => :list
      get 'message/:id' => :show
      delete 'message/:id' => :delete
    end

    ### /search

    controller :search do
      # ACL(/search/published/binary/id) TODO: direct passed call to  "pass_to_backend'
      match 'search/published/binary/id' => :pass_to_backend, via: [:get, :post]
      # ACL(/search/published/pattern/id) TODO: direct passed call to  'pass_to_backend'
      match 'search/published/pattern/id' => :pass_to_backend, via: [:get, :post]
      match 'search/channel/binary/id' => :channel_binary_id, via: [:get, :post]
      match 'search/channel/binary' => :channel_binary, via: [:get, :post]
      match 'search/channel' => :channel, via: [:get, :post]
      match 'search/released/binary/id' => :released_binary_id, via: [:get, :post]
      match 'search/released/binary' => :released_binary, via: [:get, :post]
      match 'search/project/id' => :project_id, via: [:get, :post]
      match 'search/package/id' => :package_id, via: [:get, :post]
      match 'search/project_id' => :project_id, via: [:get, :post] # FIXME3.0: to be removed
      match 'search/package_id' => :package_id, via: [:get, :post] # FIXME3.0: to be removed
      match 'search/project' => :project, via: [:get, :post]
      match 'search/package' => :package, via: [:get, :post]
      match 'search/person' => :person, via: [:get, :post]
      match 'search/attribute' => :attribute, via: [:get, :post]
      match 'search/owner' => :owner, via: [:get, :post]
      match 'search/missing_owner' => :missing_owner, via: [:get, :post]
      match 'search/request' => :bs_request, via: [:get, :post]
      match 'search/request/id' => :bs_request_id, via: [:get, :post]
      match 'search' => :pass_to_backend, via: [:get, :post]

      match 'search/repository/id' => :repository_id, via: [:get, :post]
      match 'search/issue' => :issue, via: [:get, :post]
    end

    ### /request

    resources :request, only: [:index, :show, :update, :destroy]

    post 'request' => 'request#global_command'
    post 'request/:id' => 'request#request_command', constraints: cons

    ### /lastevents

    get '/lastevents' => 'source#lastevents_public'
    match 'public/lastevents' => 'source#lastevents_public', via: [:get, :post]
    post '/lastevents' => 'source#lastevents'

    ### /distributions

    put '/distributions' => 'distributions#upload'
    # as long as the distribution IDs are integers, there is no clash
    get '/distributions/include_remotes' => 'distributions#include_remotes'
    # update is missing here
    resources :distributions, only: [:index, :show, :create, :destroy]

    ### /mail_handler

    put '/mail_handler' => 'mail_handler#upload'

    ### /cloud/upload

    scope :cloud, as: :cloud do
      resources :upload, only: [:index, :show, :create, :destroy], controller: 'cloud/upload_jobs'
    end

    ### /public
    controller :public do
      get 'public' => :index
      get 'public/about' => 'about#index'
      get 'public/configuration' => :configuration_show
      get 'public/configuration.xml' => :configuration_show
      get 'public/request/:number' => :show_request, constraints: cons
      get 'public/source/:project' => :project_index, constraints: cons
      get 'public/source/:project/_meta' => :project_meta, constraints: cons
      get 'public/source/:project/_config' => :project_file, constraints: cons
      get 'public/source/:project/_pubkey' => :project_file, constraints: cons
      get 'public/source/:project/:package' => :package_index, constraints: cons
      get 'public/source/:project/:package/_meta' => :package_meta, constraints: cons
      get 'public/source/:project/:package/:filename' => :source_file, constraints: cons
      get 'public/distributions' => :distributions
      get 'public/binary_packages/:project/:package' => :binary_packages, constraints: cons
      get 'public/build/:project(/:repository(/:arch(/:package(/:filename))))' => 'public#build', constraints: cons, as: :public_build
    end

    get '/404' => 'main#notfound'

    scope 'public' do
      resources :image_templates, constraints: cons, only: [:index], controller: 'webui/image_templates'
    end

    resources :image_templates, constraints: cons, only: [:index], controller: 'webui/image_templates'

    ### /projects
    get 'projects/:project/requests' => 'webui/projects/bs_requests#index', constraints: cons, as: 'projects_requests'
    get 'projects/:project/packages/:package/requests' => 'webui/packages/bs_requests#index', constraints: cons, as: 'packages_requests'
  end

  controller :source_attribute do
    get 'source/:project(/:package(/:binary))/_attribute(/:attribute)' => :show, constraints: cons
    post 'source/:project(/:package(/:binary))/_attribute(/:attribute)' => :update, constraints: cons, as: :change_attribute
    delete 'source/:project(/:package(/:binary))/_attribute/:attribute' => :delete, constraints: cons
  end

  # project level
  controller :source_project_meta do
    get 'source/:project/_meta' => :show, constraints: cons
    put 'source/:project/_meta' => :update, constraints: cons
  end

  controller :source_project do
    get 'source/:project' => :show, constraints: cons
    delete 'source/:project' => :delete, constraints: cons
    post 'source/:project' => :project_command, constraints: cons
  end

  controller :source_project_config do
    get 'source/:project/_config' => :show, constraints: cons
    put 'source/:project/_config' => :update, constraints: cons
  end

  controller :source do
    # package level
    get '/source/:project/_project/:filename' => :get_file, constraints: cons, defaults: { format: 'xml' }
  end

  controller :source_project_package_meta do
    get 'source/:project/:package/_meta' => :show, constraints: cons
    put 'source/:project/:package/_meta' => :update, constraints: cons
  end

  controller :source do
    get 'source' => :index
    post 'source' => :global_command_createmaintenanceincident, constraints: ->(req) { req.params[:cmd] == 'createmaintenanceincident' }
    post 'source' => :global_command_branch,                    constraints: ->(req) { req.params[:cmd] == 'branch' }
    post 'source' => :global_command_orderkiwirepos,            constraints: ->(req) { req.params[:cmd] == 'orderkiwirepos' }
    get 'source/:project/_pubkey' => :show_project_pubkey, constraints: cons
    delete 'source/:project/_pubkey' => :delete_project_pubkey, constraints: cons

    get 'source/:project/:package/:filename' => :get_file, constraints: cons, defaults: { format: 'xml' }
    delete 'source/:project/:package/:filename' => :delete_file, constraints: cons
    put 'source/:project/:package/:filename' => :update_file, constraints: cons

    get 'source/:project/:package' => :show_package, constraints: cons
    post 'source/:project/:package' => :package_command, constraints: cons
    delete 'source/:project/:package' => :delete_package, constraints: cons
  end

  scope module: :status, path: :status_reports do
    resources :projects, only: [], param: :name, constraints: cons do
      resources :required_checks, only: [:index, :create, :destroy], param: :name
    end

    scope :repositories do
      resources :projects, only: [], param: :name, path: '', constraints: cons do
        resources :repositories, only: [], param: :name, path: '', constraints: cons do
          resources :required_checks, only: [:index, :create, :destroy], param: :name
        end
      end
    end

    controller :reports do
      scope :published do
        get ':project_name/:repository_name/reports/:report_uuid' => :show, constraints: cons
      end
      scope :built do
        get ':project_name/:repository_name/:arch/reports/:report_uuid' => :show, constraints: cons
      end
      scope :requests do
        get ':bs_request_number/reports' => :show
      end
    end
    controller :checks do
      scope :published do
        post ':project_name/:repository_name/reports/:report_uuid' => :update, constraints: cons
      end
      scope :built do
        post ':project_name/:repository_name/:arch/reports/:report_uuid' => :update, constraints: cons
      end
      scope :requests do
        post ':bs_request_number/reports' => :update
      end
    end
  end

  defaults format: 'xml' do
    controller :comments do
      get 'comments/request/:request_number' => :index, constraints: cons, as: :comments_request
      post 'comments/request/:request_number' => :create, constraints: cons, as: :create_request_comment
      get 'comments/package/:project/:package' => :index, constraints: cons, as: :comments_package
      post 'comments/package/:project/:package' => :create, constraints: cons, as: :create_package_comment
      get 'comments/project/:project' => :index, constraints: cons, as: :comments_project
      post 'comments/project/:project' => :create, constraints: cons, as: :create_project_comment
      get 'comments/user' => :index, constraints: cons, as: :comments_user

      delete 'comment/:id' => :destroy, constraints: cons, as: :comment_delete
    end
  end

  # this can be requested by non browsers (like HA proxies :)
  get 'apidocs/:filename' => 'webui/apidocs#file', constraints: cons, as: 'apidocs_file'

  # spiders request this, not browsers
  controller 'webui/sitemaps' do
    get 'sitemaps' => :index
    get 'project/sitemap' => :projects
    get 'package/sitemap(/:project_name)' => :packages
  end
end

OBSEngine::Base.subclasses.each(&:mount_it)
