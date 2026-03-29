# app/services/interview_engine/question_selector.rb
module InterviewEngine
  class QuestionSelector
    def initialize(interview)
      @interview = interview
      @situation = interview.situation
      @preloaded_responses = interview.interview_responses.includes(:question).to_a
    end

    # Get next eligible question (considering branching rules)
    def get_next_question
      next_q = eligible_questions.first

      raise "All questions answered" if next_q.nil?
      raise "No questions in situation" if @situation.questions.empty?

      next_q
    end

    # Get question text and generate TTS audio
    def prepare_question_audio(question, language: 'en')
      audio_record = ensure_question_audio(question, language)

      {
        question_id: question.id,
        question_text: question.question_text,
        question_type: question.question_type,
        audio_url: audio_record&.audio&.attached? ? audio_url(audio_record.audio) : nil,
        order: question.order,
        required: question.required?,
        total_questions: total_eligible_count,
        options: question.multiple_choice? ? question.parsed_options : nil,
        avatar_url: avatar_url
      }
    end

    # Get question without audio (text only)
    def get_question_text(question)
      {
        question_id: question.id,
        question_text: question.question_text,
        question_type: question.question_type,
        order: question.order,
        required: question.required?,
        total_questions: total_eligible_count,
        options: question.multiple_choice? ? question.parsed_options : nil,
        avatar_url: avatar_url
      }
    end

    # Check if interview should continue
    def should_continue_interview?
      eligible_questions.any?
    end

    private

    # All unanswered questions (no branching filter)
    def unanswered_questions
      @interview.situation.questions.where.not(
        id: @interview.interview_responses.select(:question_id)
      ).order(:order)
    end

    # Unanswered questions filtered by branching rules
    def eligible_questions
      @eligible_questions ||= unanswered_questions.select { |q| evaluate_branching_rules(q) }
    end

    # Reset memoized cache (call after a new response is submitted)
    def reset_cache!
      @eligible_questions = nil
    end

    # Total count of eligible questions (answered + remaining eligible)
    def total_eligible_count
      answered_count = @preloaded_responses.size
      answered_count + eligible_questions.size
    end

    # Evaluate branching rules for a question
    # Returns true if the question should be included
    def evaluate_branching_rules(question)
      return true unless question.has_branching_rules?

      rules = question.parsed_branching_rules
      return true if rules.nil?

      conditions = rules[:conditions]
      default_action = rules[:default_action] || 'include'

      return default_action == 'include' if conditions.blank?

      conditions.each do |condition|
        result = evaluate_condition(condition)
        action = condition[:action] || 'include'

        if result
          return action == 'include'
        end
      end

      # No condition matched — use default
      default_action == 'include'
    end

    # Evaluate a single branching condition
    def evaluate_condition(condition)
      source_order = condition[:source_question_order]
      return false if source_order.nil?

      response = find_response_for_question_order(source_order)

      case condition[:type]
      when 'selected_option'
        return false if response.nil?
        response.audio_transcript.to_s.strip.downcase == condition[:value].to_s.strip.downcase
      when 'score_above'
        return false if response.nil? || response.final_score.nil?
        response.final_score >= condition[:value].to_f
      when 'score_below'
        return false if response.nil? || response.final_score.nil?
        response.final_score < condition[:value].to_f
      when 'answered'
        response.present?
      else
        false
      end
    end

    # Find InterviewResponse by question order number (メモリ上で検索)
    def find_response_for_question_order(order)
      @preloaded_responses.find { |r| r.question.order == order }
    end

    def ensure_question_audio(question, language)
      record = QuestionAudio.find_or_initialize_by(question: question, language: language)
      return record if record.audio.attached?

      begin
        tts_client = TTSClient.new
        audio_path = tts_client.speak(question.question_text, language: language)
        return record if audio_path.nil?

        File.open(audio_path, 'rb') do |file|
          record.audio.attach(
            io: file,
            filename: File.basename(audio_path),
            content_type: 'audio/mpeg'
          )
        end

        record.save!
      rescue => e
        Rails.logger.error("TTS音声生成に失敗しました (Question ##{question.id}): #{e.message}")
      end

      record
    end

    def audio_url(audio_attachment)
      Rails.application.routes.url_helpers.rails_blob_path(audio_attachment, only_path: true)
    end

    def avatar_url
      ActionController::Base.helpers.asset_path('image.png')
    end
  end
end
