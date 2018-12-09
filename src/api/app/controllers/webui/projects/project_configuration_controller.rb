module Webui
  module Projects
    class ProjectConfigurationController < WebuiController
      before_action :set_project

      def show
        sliced_params = params.slice(:rev)
        sliced_params.permit!
        @content = @project.config.content(sliced_params.to_h)
        switch_to_webui2
        return if @content
        flash[:error] = @project.config.errors.full_messages.to_sentence
        redirect_to controller: 'project', nextstatus: 404
      end

      def update
        authorize @project, :update?

        params[:user] = User.current.login
        sliced_params = params.slice(:user, :comment)
        sliced_params.permit!

        content = @project.config.save(sliced_params.to_h, params[:config])

        status = if content
                  flash.now[:success] = 'Config successfully saved!'
                  200
                else
                  flash.now[:error] = @project.config.errors.full_messages.to_sentence
                  400
                end
        switch_to_webui2
        render layout: false, status: status, partial: "layouts/#{view_namespace}/flash", object: flash
      end

      private

      def view_namespace
        switch_to_webui2? ? 'webui2' : 'webui'
      end
    end
  end
end
