require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:interviews).dependent(:destroy) }
    it { is_expected.to have_many(:interview_results).through(:interviews) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'requires email' do
      user = build(:user, email: '')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it 'requires unique email' do
      create(:user, email: 'duplicate@example.com')
      user = build(:user, email: 'duplicate@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it 'requires password with minimum length' do
      user = build(:user, password: 'short')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end
  end

  describe 'Devise modules' do
    it 'is database_authenticatable' do
      expect(User.devise_modules).to include(:database_authenticatable)
    end

    it 'is registerable' do
      expect(User.devise_modules).to include(:registerable)
    end

    it 'is recoverable' do
      expect(User.devise_modules).to include(:recoverable)
    end

    it 'is rememberable' do
      expect(User.devise_modules).to include(:rememberable)
    end

    it 'is validatable' do
      expect(User.devise_modules).to include(:validatable)
    end
  end

  describe 'interview_results through interviews' do
    it 'accesses results through interviews' do
      user = create(:user)
      client = create(:client)
      situation = create(:situation, :with_questions, client: client)
      interview = create(:interview, :completed, user: user, situation: situation)
      result = create(:interview_result, interview: interview)

      expect(user.interview_results).to include(result)
    end
  end

  describe 'dependent destroy' do
    it 'destroys interviews when user is destroyed' do
      user = create(:user)
      client = create(:client)
      situation = create(:situation, :with_questions, client: client)
      create(:interview, user: user, situation: situation)

      expect { user.destroy }.to change(Interview, :count).by(-1)
    end
  end
end
