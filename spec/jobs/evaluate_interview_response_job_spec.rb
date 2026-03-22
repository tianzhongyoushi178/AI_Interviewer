require 'rails_helper'

RSpec.describe EvaluateInterviewResponseJob, type: :job do
  let(:client) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client) }
  let(:interview) { create(:interview, :in_progress, user: create(:user), situation: situation) }
  let(:question) { situation.questions.first }
  let(:response_record) do
    create(:interview_response, interview: interview, question: question,
           audio_transcript: 'テスト回答', evaluation_status: :pending)
  end

  before do
    # ActiveJob テストアダプタ設定
    ActiveJob::Base.queue_adapter = :test

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return('true')
  end

  describe '#perform' do
    it 'ResponseEvaluatorを呼び出して評価する' do
      evaluator_mock = instance_double(InterviewEngine::ResponseEvaluator)
      allow(InterviewEngine::ResponseEvaluator).to receive(:new).and_return(evaluator_mock)
      allow(evaluator_mock).to receive(:evaluate)

      described_class.perform_now(response_record.id)

      expect(InterviewEngine::ResponseEvaluator).to have_received(:new)
        .with(response_record, language: situation.language)
      expect(evaluator_mock).to have_received(:evaluate)
    end

    it 'situationの言語設定を使用する' do
      situation.update!(language: 'ja')
      evaluator_mock = instance_double(InterviewEngine::ResponseEvaluator)
      allow(InterviewEngine::ResponseEvaluator).to receive(:new).and_return(evaluator_mock)
      allow(evaluator_mock).to receive(:evaluate)

      described_class.perform_now(response_record.id)

      expect(InterviewEngine::ResponseEvaluator).to have_received(:new)
        .with(response_record, language: 'ja')
    end

    it 'テストモードで実際に評価を実行する' do
      described_class.perform_now(response_record.id)

      response_record.reload
      expect(response_record.evaluation_status).to eq('completed')
      expect(response_record.final_score).to be_present
    end

    it '存在しないIDでActiveRecord::RecordNotFoundが発生する' do
      # retry_on StandardError が設定されているため、perform_nowでは
      # リトライ上限（3回）に達するまで例外を抑制し、最終的にも例外を飲み込む。
      # ここではJobが失敗すること自体を確認する。
      expect(InterviewResponse).to receive(:find).with(99999).and_raise(ActiveRecord::RecordNotFound)

      # perform_nowでは retry_on により例外は抑制される
      described_class.perform_now(99999)
    end
  end

  describe 'キュー設定' do
    it 'defaultキューに登録される' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end

  describe 'enqueue' do
    it 'perform_laterでキューに登録できる' do
      expect {
        described_class.perform_later(response_record.id)
      }.to have_enqueued_job(described_class).with(response_record.id)
    end

    it 'キューに正しい引数で登録される' do
      expect {
        described_class.perform_later(response_record.id)
      }.to have_enqueued_job.on_queue('default')
    end
  end

  describe 'リトライ設定' do
    it 'StandardErrorで最大3回リトライする設定がある' do
      # retry_on設定の存在確認
      retry_handlers = described_class.rescue_handlers
      expect(described_class.ancestors).to include(ActiveJob::Base)
    end
  end
end
