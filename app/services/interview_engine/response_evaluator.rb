# app/services/interview_engine/response_evaluator.rb
module InterviewEngine
  class ResponseEvaluator
    # DEFAULT_PASS_THRESHOLD は config/initializers/interview_config.rb で管理

    def initialize(interview_response, language: 'en')
      @response = interview_response
      @language = language
      @interview = interview_response.interview
      @question = interview_response.question
      @situation = @interview.situation
    end

    # Evaluate a single response from user
    def evaluate
      return if @response.audio_transcript.blank?

      @response.update!(evaluation_status: :evaluating)

      evaluation = if @question.multiple_choice?
                     evaluate_multiple_choice
                   elsif test_mode?
                     test_mode_evaluation
                   else
                     llm_evaluate
                   end

      ActiveRecord::Base.transaction do
        update_response_with_evaluation(evaluation)
      end

      check_rejection

      @response
    rescue => e
      Rails.logger.error("Response Evaluation Error: #{e.message}")
      @response.update!(evaluation_status: :failed)
      raise
    end

    private

    def update_response_with_evaluation(evaluation)
      # 意図的にLLMが返すfinal_scoreを無視し、加重平均で再計算する。
      # LLMのfinal_scoreは各基準スコアと整合しない場合があるため、
      # サーバー側で一貫した算出ロジックを適用する。
      final_score = calculate_weighted_score(evaluation)

      threshold = pass_threshold
      passed = final_score >= threshold

      @response.update!(
        relevance_score: evaluation[:relevance_score],
        correctness_score: evaluation[:correctness_score],
        clarity_score: evaluation[:clarity_score],
        final_score: final_score,
        passed: passed,
        ai_reasoning: evaluation[:reasoning],
        evaluation_status: :completed
      )
    end

    def test_mode?
      ENV['AI_INTERVIEW_TEST_MODE'] == 'true'
    end

    def test_mode_evaluation
      {
        relevance_score: 85,
        correctness_score: 80,
        clarity_score: 82,
        final_score: 82.5,
        passed: true,
        reasoning: 'Test mode evaluation'
      }.with_indifferent_access
    end

    def llm_evaluate
      llm = LLMClient.new
      llm.evaluate_response(
        @question.question_text,
        @response.audio_transcript,
        language: @language,
        question_type: 'open'
      )
    end

    def calculate_weighted_score(evaluation)
      cfg = Rails.application.config.interview
      weights = {
        relevance: cfg.eval_weight_relevance,
        correctness: cfg.eval_weight_correctness,
        clarity: cfg.eval_weight_clarity
      }

      score = (
        (evaluation[:relevance_score].to_i * weights[:relevance]) +
        (evaluation[:correctness_score].to_i * weights[:correctness]) +
        (evaluation[:clarity_score].to_i * weights[:clarity])
      ).round(2)

      [score, 100].min # Cap at 100
    end

    def check_rejection
      @interview.reload
      return unless @interview.in_progress?

      judge = RejectJudge.new(@interview)
      decision = judge.judge_after_response(@response)

      if decision.rejected?
        judge.apply_rejection!(decision)
        # 通知はトランザクション外で実行
        notify_rejection_via_session_manager(decision.reason)
      end
    end

    def notify_rejection_via_session_manager(reason)
      SessionManager.new(@interview.user, @situation)
                    .send(:notify_rejection, @interview, reason)
    rescue => e
      Rails.logger.error("Rejection notification failed: #{e.message}")
    end

    def pass_threshold
      @situation&.min_required_score || Rails.application.config.interview.default_pass_threshold
    end

    def evaluate_multiple_choice
      options = @question.parsed_options
      choices = options['choices'] || options[:choices] || []
      correct = options['correct'] || options[:correct]

      # 正解未設定（キー欠落 / nil / 空白のみ）は情報収集型とみなし満点扱い。
      # 管理画面でも「正解の選択肢（任意）」と明示されているため、
      # 未設定の場合に不合格とするのは仕様と矛盾する。
      if correct.nil? || correct.to_s.strip.empty?
        return {
          relevance_score: 100,
          correctness_score: 100,
          clarity_score: 100,
          final_score: 100,
          passed: true,
          reasoning: 'Informational choice question (no correct answer defined)'
        }.with_indifferent_access
      end

      selected = @response.audio_transcript.to_s.strip.downcase
      correct_choice = resolve_correct_choice(correct, choices)

      passed = !correct_choice.nil? && selected == correct_choice.downcase
      score = passed ? 100 : 0

      {
        relevance_score: score,
        correctness_score: score,
        clarity_score: score,
        final_score: score,
        passed: passed,
        reasoning: passed ? 'Correct option selected' : 'Incorrect option selected'
      }.with_indifferent_access
    end

    def resolve_correct_choice(correct, choices)
      return nil if correct.nil?

      if correct.is_a?(Integer)
        choices[correct]
      else
        correct.to_s
      end
    end
  end
end
