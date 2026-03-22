require 'rails_helper'

RSpec.describe Admin, type: :model do
  describe 'validations' do
    it 'requires email' do
      admin = build(:admin, email: '')
      expect(admin).not_to be_valid
      expect(admin.errors[:email]).to be_present
    end

    it 'requires unique email' do
      create(:admin, email: 'admin@example.com')
      admin = build(:admin, email: 'admin@example.com')
      expect(admin).not_to be_valid
      expect(admin.errors[:email]).to be_present
    end

    it 'requires valid email format' do
      admin = build(:admin, email: 'invalid-email')
      expect(admin).not_to be_valid
    end

    it 'requires password with minimum length' do
      admin = build(:admin, password: 'short')
      expect(admin).not_to be_valid
      expect(admin.errors[:password]).to be_present
    end

    it 'creates with valid attributes' do
      admin = build(:admin)
      expect(admin).to be_valid
    end
  end

  describe 'Devise modules' do
    it 'includes expected modules' do
      expected_modules = [:database_authenticatable, :registerable, :recoverable, :rememberable, :validatable]
      expected_modules.each do |mod|
        expect(Admin.devise_modules).to include(mod)
      end
    end
  end

  describe 'authentication' do
    it 'authenticates with correct password' do
      admin = create(:admin, password: 'secure_password123')
      expect(admin.valid_password?('secure_password123')).to be true
    end

    it 'rejects incorrect password' do
      admin = create(:admin, password: 'secure_password123')
      expect(admin.valid_password?('wrong_password')).to be false
    end
  end
end
