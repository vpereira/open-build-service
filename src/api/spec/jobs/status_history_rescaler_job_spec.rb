require 'rails_helper'

RSpec.describe StatusHistoryRescalerJob, type: :job do
  include ActiveJob::TestHelper

  describe '#rescale' do
    let(:now) { Time.now.to_i - 2.days }
    let(:idle_status_histories) { StatusHistory.where(key: 'idle_x86_64') }
    let(:busy_status_histories) { StatusHistory.where(key: 'busy_x86_64') }

    let(:initial_busy_status_histories) do
      10.times { |i| StatusHistory.create(time: now - i.hours.to_i, key: 'busy_x86_64', value: i) }
    end

    let(:initial_idle_status_histories) do
      10.times { |i| StatusHistory.create(time: now - i.hours.to_i, key: 'idle_x86_64', value: i) }
    end

    let(:average_busy_time) do
      busy_status_histories.average(:time)
    end

    let(:average_busy_value) do
      busy_status_histories.average(:value)
    end

    let(:average_idle_time) do
      idle_status_histories.average(:time)
    end

    let(:average_idle_value) do
      idle_status_histories.average(:value)
    end

    before do
      initial_busy_status_histories
      initial_idle_status_histories
    end

    subject! { StatusHistoryRescalerJob.perform_now }

    context 'StatusHistory Total' do
      it { expect(StatusHistory.count).to eq(2) }
    end

    context 'Status histories for idle_x86_64' do
      it { expect(idle_status_histories.count).to eq(1) }
      it { expect(idle_status_histories.first.value).to eq(average_idle_value) }
      it { expect(idle_status_histories.first.time).to eq(average_idle_time) }
    end

    context 'Status histories for busy_x86_64' do
      it { expect(busy_status_histories.count).to eq(1) }
      it { expect(busy_status_histories.first.value).to eq(average_busy_value) }
      it { expect(busy_status_histories.first.time).to eq(average_busy_time) }
    end
  end
end
