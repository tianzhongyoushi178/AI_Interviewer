require 'rails_helper'

RSpec.describe Contract, type: :model do
  describe 'company validation' do
    it 'is valid when company includes 会社' do
      contract = Contract.new(company: 'テスト株式会社')
      contract.valid?
      expect(contract.errors[:company]).to be_empty
    end

    it 'is valid when company includes 組合' do
      contract = Contract.new(company: 'テスト協同組合')
      contract.valid?
      expect(contract.errors[:company]).to be_empty
    end

    it 'is invalid when company does not include 会社 or 組合' do
      contract = Contract.new(company: 'テスト事務所')
      expect(contract).not_to be_valid
      expect(contract.errors[:company]).to include('には「敬称」を含める必要があります')
    end

    it 'is invalid when company is nil' do
      contract = Contract.new(company: nil)
      expect(contract).not_to be_valid
      expect(contract.errors[:company]).to include('には「敬称」を含める必要があります')
    end

    it 'is invalid when company is empty string' do
      contract = Contract.new(company: '')
      expect(contract).not_to be_valid
      expect(contract.errors[:company]).to include('には「敬称」を含める必要があります')
    end
  end

  describe 'attributes' do
    it 'stores all contact information' do
      contract = Contract.create!(
        company: '株式会社テスト',
        name: '山田太郎',
        tel: '03-1234-5678',
        email: 'yamada@example.com',
        address: '東京都渋谷区',
        url: 'https://example.com',
        service: 'コンサルティング',
        period: '1年',
        message: 'お問い合わせです'
      )

      expect(contract.name).to eq('山田太郎')
      expect(contract.tel).to eq('03-1234-5678')
      expect(contract.email).to eq('yamada@example.com')
      expect(contract.address).to eq('東京都渋谷区')
      expect(contract.url).to eq('https://example.com')
      expect(contract.service).to eq('コンサルティング')
      expect(contract.period).to eq('1年')
      expect(contract.message).to eq('お問い合わせです')
    end
  end
end
