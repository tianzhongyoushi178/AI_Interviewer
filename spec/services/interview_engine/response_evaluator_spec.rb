require 'rails_helper'

RSpec.describe InterviewEngine::ResponseEvaluator do
  let(:client) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client) }
  let(:interview) { create(:interview, :in_progress, user: create(:user), situation: situation) }
  let(:question) { situation.questions.first }
  let(:response_record) do
    create(:interview_response, interview: interview, question: question,
           audio_transcript: 'テスト回答です', evaluation_status: :pending)
  end

  let(:evaluator) { described_class.new(response_record, language: 'ja') }

  describe '#evaluate' do
    context 'テストモード' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return('true')
      end

      it 'テストモードの固定スコアで評価する' do
        result = evaluator.evaluate

        expect(result.evaluation_status).to eq('completed')
        expect(result.relevance_score).to be_present
        expect(result.correctness_score).to be_present
        expect(result.clarity_score).to be_present
      end
    end

    context 'LLM評価' do
      let(:llm_mock) { instance_double(InterviewEngine::LLMClient) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return(nil)
        allow(InterviewEngine::LLMClient).to receive(:new).and_return(llm_mock)
      end

      it 'LLMの評価結果を保存する' do
        allow(llm_mock).to receive(:evaluate_response).and_return({
          relevance_score: 85,
          correctness_score: 80,
          clarity_score: 90,
          final_score: 85,
          passed: true,
          reasoning: '良い回答'
        }.with_indifferent_access)

        result = evaluator.evaluate

        expect(result.evaluation_status).to eq('completed')
        expect(result.ai_reasoning).to eq('良い回答')
      end

      it '加重平均スコアを再計算する' do
        allow(llm_mock).to receive(:evaluate_response).and_return({
          relevance_score: 80,
          correctness_score: 70,
          clarity_score: 60,
          final_score: 999, # LLMのfinal_scoreは無視される
          passed: true,
          reasoning: 'test'
        }.with_indifferent_access)

        result = evaluator.evaluate

        # デフォルト重み: relevance 0.4, correctness 0.4, clarity 0.2
        expected = (80 * 0.4 + 70 * 0.4 + 60 * 0.2).round(2)
        expect(result.final_score).to eq(expected)
      end

      it 'スコアが合格ライン以上の場合passedがtrueになる' do
        allow(llm_mock).to receive(:evaluate_response).and_return({
          relevance_score: 90,
          correctness_score: 90,
          clarity_score: 90,
          final_score: 90,
          passed: true,
          reasoning: '優秀'
        }.with_indifferent_access)

        result = evaluator.evaluate
        expect(result.passed).to eq(true)
      end

      it 'スコアが合格ライン未満の場合passedがfalseになる' do
        allow(llm_mock).to receive(:evaluate_response).and_return({
          relevance_score: 30,
          correctness_score: 20,
          clarity_score: 10,
          final_score: 20,
          passed: false,
          reasoning: '不十分'
        }.with_indifferent_access)

        result = evaluator.evaluate
        expect(result.passed).to eq(false)
      end
    end

    context '選択式問題' do
      let(:mc_question) do
        create(:question, :multiple_choice, situation: situation,
               options: { 'choices' => %w[選択肢A 選択肢B 選択肢C], 'correct' => '選択肢A' })
      end
      let(:mc_response) do
        create(:interview_response, interview: interview, question: mc_question,
               audio_transcript: '選択肢A', evaluation_status: :pending)
      end
      let(:mc_evaluator) { described_class.new(mc_response, language: 'ja') }

      it '正解の場合はスコア100で合格する' do
        result = mc_evaluator.evaluate

        expect(result.final_score).to eq(100)
        expect(result.passed).to eq(true)
        expect(result.evaluation_status).to eq('completed')
      end

      it '不正解の場合はスコア0で不合格になる' do
        mc_response.update!(audio_transcript: '選択肢B')
        evaluator = described_class.new(mc_response, language: 'ja')

        result = evaluator.evaluate

        expect(result.final_score).to eq(0)
        expect(result.passed).to eq(false)
      end

      it '大文字小文字を区別しない' do
        mc_question.update!(options: { 'choices' => %w[OptionA OptionB], 'correct' => 'OptionA' })
        mc_response.update!(audio_transcript: 'optiona')
        evaluator = described_class.new(mc_response, language: 'en')

        result = evaluator.evaluate
        expect(result.passed).to eq(true)
      end

      context '正解未設定の情報収集型選択肢' do
        # 管理画面で「正解の選択肢（任意）」が未入力の場合、情報収集目的の質問とみなし、
        # 選択されたいずれの選択肢も満点・合格として扱う。
        it 'correctキーが存在しない場合は満点で合格にする' do
          mc_question.update!(options: { 'choices' => %w[Ruby Python Go] })
          mc_response.update!(audio_transcript: 'Ruby')
          evaluator = described_class.new(mc_response, language: 'ja')

          result = evaluator.evaluate

          expect(result.final_score).to eq(100)
          expect(result.passed).to eq(true)
          expect(result.ai_reasoning).to match(/informational|情報収集/i)
        end

        it 'correctが空文字の場合は満点で合格にする' do
          mc_question.update!(options: { 'choices' => %w[Ruby Python Go], 'correct' => '' })
          mc_response.update!(audio_transcript: 'Python')
          evaluator = described_class.new(mc_response, language: 'ja')

          result = evaluator.evaluate

          expect(result.final_score).to eq(100)
          expect(result.passed).to eq(true)
        end

        it 'correctがnilの場合は満点で合格にする' do
          mc_question.update!(options: { 'choices' => %w[Ruby Python Go], 'correct' => nil })
          mc_response.update!(audio_transcript: 'Go')
          evaluator = described_class.new(mc_response, language: 'ja')

          result = evaluator.evaluate

          expect(result.final_score).to eq(100)
          expect(result.passed).to eq(true)
        end

        it 'correctが空白文字のみの場合は満点で合格にする' do
          mc_question.update!(options: { 'choices' => %w[Ruby Python], 'correct' => '   ' })
          mc_response.update!(audio_transcript: 'Ruby')
          evaluator = described_class.new(mc_response, language: 'ja')

          result = evaluator.evaluate

          expect(result.final_score).to eq(100)
          expect(result.passed).to eq(true)
        end

        it '必須質問であっても情報収集型ならリジェクト判定が発火しない' do
          mc_question.update!(options: { 'choices' => %w[Ruby Python Go] }, required: true)
          mc_response.update!(audio_transcript: 'Ruby')
          evaluator = described_class.new(mc_response, language: 'ja')

          result = evaluator.evaluate

          interview.reload
          expect(interview.status).to eq('in_progress')
          expect(interview.rejection_reason).to be_nil
          expect(result.passed).to eq(true)
        end
      end
    end

    context 'エラーハンドリング' do
      it 'audio_transcriptが空の場合は何も実行しない' do
        response_record.update_column(:audio_transcript, '')
        result = evaluator.evaluate
        expect(result).to be_nil
      end

      it 'LLM呼び出しが失敗した場合はevaluation_statusをfailedにする' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return(nil)

        llm_mock = instance_double(InterviewEngine::LLMClient)
        allow(InterviewEngine::LLMClient).to receive(:new).and_return(llm_mock)
        allow(llm_mock).to receive(:evaluate_response).and_raise(StandardError, 'API Error')

        expect {
          evaluator.evaluate
        }.to raise_error(StandardError)

        response_record.reload
        expect(response_record.evaluation_status).to eq('failed')
      end
    end

    context 'リジェクション判定' do
      it '評価後にRejectJudgeが呼ばれる' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return('true')

        judge_mock = instance_double(InterviewEngine::RejectJudge)
        decision = InterviewEngine::RejectJudge::RejectDecision.new(
          rejected: false, reason: nil, details: nil
        )
        allow(InterviewEngine::RejectJudge).to receive(:new).and_return(judge_mock)
        allow(judge_mock).to receive(:judge_after_response).and_return(decision)

        evaluator.evaluate

        expect(judge_mock).to have_received(:judge_after_response)
      end
    end
  end
end
