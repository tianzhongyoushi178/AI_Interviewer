require 'rails_helper'

RSpec.describe QuestionAudio, type: :model do
  let(:client) { create(:client) }
  let(:situation) { create(:situation, client: client) }
  let(:question) { create(:question, situation: situation) }

  describe 'associations' do
    it { is_expected.to belong_to(:question) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:language) }

    it 'is valid with required attributes' do
      audio = QuestionAudio.new(question: question, language: 'ja')
      expect(audio).to be_valid
    end

    it 'is invalid without language' do
      audio = QuestionAudio.new(question: question, language: nil)
      expect(audio).not_to be_valid
      expect(audio.errors[:language]).to be_present
    end

    it 'is invalid without question' do
      audio = QuestionAudio.new(language: 'ja')
      expect(audio).not_to be_valid
      expect(audio.errors[:question]).to be_present
    end
  end

  describe 'uniqueness' do
    it 'prevents duplicate question+language combination at DB level' do
      QuestionAudio.create!(question: question, language: 'ja')
      duplicate = QuestionAudio.new(question: question, language: 'ja')
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows same question with different language' do
      QuestionAudio.create!(question: question, language: 'ja')
      different_lang = QuestionAudio.new(question: question, language: 'en')
      expect(different_lang).to be_valid
    end
  end

  describe 'languages' do
    it 'supports English' do
      audio = QuestionAudio.create!(question: question, language: 'en')
      expect(audio.language).to eq('en')
    end

    it 'supports Japanese' do
      audio = QuestionAudio.create!(question: question, language: 'ja')
      expect(audio.language).to eq('ja')
    end
  end
end
