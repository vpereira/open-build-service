require 'rails_helper'

RSpec.describe Token::ReleasePolicy do
  let!(:user) { create(:confirmed_user, login: 'foo') }
  let!(:project) { create(:project, maintainer: user) }
  let!(:package) { create(:package, project: project) }
  let!(:other_user) { build(:confirmed_user, login: 'bar') }
  let!(:release_token) { create(:release_token, :with_package_from_association_or_param, user: user, package: package) }
  let!(:other_user_release_token) { create(:release_token, :with_package_from_association_or_param, user: other_user) }

  subject { described_class }

  describe '#create' do
    permissions :create? do
      it { expect(subject).to permit(user, release_token) }
      it { expect(subject).not_to permit(other_user, other_user_release_token) }
    end
  end
end