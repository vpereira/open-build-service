require 'statistics_calculations'

class Webui::MainController < Webui::WebuiController
  skip_before_action :check_anonymous, only: [:index]

  def index
    @status_messages = StatusMessage.newest.for_current_user.includes(:user).limit(4)
    @workerstatus = Rails.cache.fetch('workerstatus_hash', expires_in: 10.minutes) do
      Xmlhash.parse(WorkerStatus.hidden.to_xml)
    end
    @latest_updates = StatisticsCalculations.get_latest_updated(6)
    @waiting_packages = 0
    @building_workers = @workerstatus.elements('building').length
    @overall_workers = @workerstatus['clients']
    @workerstatus.elements('waiting') { |waiting| @waiting_packages += waiting['jobs'].to_i }
    @busy = Rails.cache.fetch('mainpage_busy', expires_in: 10.minutes) do
      gather_busy
    end

    @system_stats = Rails.cache.fetch('system_stats_hash', expires_in: 30.minutes) do
      {
        projects: Project.count,
        packages: Package.count,
        repositories: Repository.count,
        users: User.count
      }
    end
  end

  private

  def gather_busy
    StatusHelper.resample(building_status_history, 400)
  end

  def building_status_history
    StatusHistory.where("time >= ? AND \`key\` LIKE ?", 24.hours.ago.to_i, 'building_%')
                 .pluck(:time, :value)
  end
end
