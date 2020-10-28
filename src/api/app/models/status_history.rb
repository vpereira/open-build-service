class StatusHistory < ApplicationRecord
  default_scope { order(:time) }

  def self.history_by_key_and_hours(key, hours = 24)
    starttime = Time.now.to_i - hours.to_i * 3600

    where("time >= ? AND \`key\` = ?", starttime, key)
      .pluck(:time, :value)
      .collect! { |time, value| [time.to_i, value.to_f] }
  end
end

# == Schema Information
#
# Table name: status_histories
#
#  id    :integer          not null, primary key
#  key   :string(255)      indexed, indexed => [time]
#  time  :integer          indexed => [key]
#  value :float(24)        not null
#
# Indexes
#
#  index_status_histories_on_key           (key)
#  index_status_histories_on_time_and_key  (time,key)
#
