class StatusHistoryRescalerJob < ApplicationJob
  queue_as :quick

  # this is called from a delayed job triggered by clockwork
  def perform
    distinct_status_history_keys.each do |key|
      StatusHistory.transaction do
        # first rescale a month old
        cleanup(key, 12.hours.ago, 1.month.ago)
        # now a week old
        cleanup(key, 6.hours.ago, 7.days.ago)
        # now rescale yesterday
        cleanup(key, 1.hour.ago, 24.hours.ago)
        # 2h stuff
        cleanup(key, 4.minutes.ago, 2.hours.ago)
      end
    end
  end

  private

  def distinct_status_history_keys
    StatusHistory.distinct.pluck(:key)
  end

  def find_items(key, mintime, maxtime)
    StatusHistory.where(key: key, time: maxtime..mintime)
  end

  def cleanup(key, mintime, maxtime)
    # we try to make sure all keys are in the same time slots,
    # so start with the overall time
    allitems = find_items(key, mintime, maxtime)
    return if allitems.empty?

    time_average = allitems.average(:time)
    value_average = allitems.average(:value)
    allitems.delete_all
    StatusHistory.create(key: key, time: time_average, value: value_average)
  end
end
