# app/controllers/api/interviews_controller.rb
module Api
  class InterviewsController < ApplicationController
    skip_before_action :verify_authenticity_token
    include ApiErrorHandler
    include FileUploadValidation

    before_action :verify_content_type!, only: [:start, :start_by_token, :submit_answer, :complete, :resume]
    before_action :authenticate_by_token_or_user!, except: [:start_by_token, :start]
    before_action :authenticate_or_create_guest!, only: [:start]
    before_action :set_interview, only: [:next_question, :submit_answer, :complete, :status, :resume]
    before_action :check_session_timeout!, only: [:next_question, :submit_answer]

    # POST /api/interviews/start
    def start
      situation = Situation.find(params[:situation_id])
      language = params[:language].presence || situation.language || 'en'

      session_manager = InterviewEngine::SessionManager.new(@current_user, situation)
      interview = session_manager.start_interview(language: language)

      render json: {
        success: true,
        interview_id: interview.id,
        access_token: interview.access_token,
        status: interview.status,
        total_questions: interview.total_questions,
        language: interview.language,
        session_timeout_minutes: situation.session_timeout_minutes,
        remaining_seconds: interview.remaining_seconds
      }, status: :created
    rescue InterviewEngine::SessionManager::SessionError => e
      render_api_error(e.message, status: :unprocessable_entity)
    end

    # POST /api/interviews/start_by_token
    def start_by_token
      access_token = params[:access_token]
      unless access_token.present?
        return render_api_error('access_token is required', status: :bad_request)
      end

      interview = InterviewEngine::SessionManager.start_by_token(access_token)

      render json: {
        success: true,
        interview_id: interview.id,
        status: interview.status,
        total_questions: interview.total_questions,
        language: interview.language,
        progress: interview.progress_percentage,
        answered_questions: interview.answered_question_count,
        session_timeout_minutes: interview.situation.session_timeout_minutes,
        remaining_seconds: interview.remaining_seconds,
        resume_count: interview.resume_count
      }
    rescue InterviewEngine::SessionManager::TimeoutError => e
      render_api_error(e.message, status: :gone, reason: 'timeout')
    rescue InterviewEngine::SessionManager::ResumeError => e
      render_api_error(e.message, status: :forbidden, reason: 'resume_limit')
    rescue InterviewEngine::SessionManager::SessionError => e
      render_api_error(e.message, status: :unprocessable_entity)
    end

    # POST /api/interviews/:id/resume
    def resume
      session_manager = InterviewEngine::SessionManager.new(@interview.user, @interview.situation)
      interview = session_manager.resume_interview(@interview.id)

      render json: {
        success: true,
        interview_id: interview.id,
        status: interview.status,
        progress: interview.progress_percentage,
        answered_questions: interview.answered_question_count,
        total_questions: interview.total_questions,
        remaining_seconds: interview.remaining_seconds,
        resume_count: interview.resume_count
      }
    rescue InterviewEngine::SessionManager::ResumeError => e
      render_api_error(e.message, status: :forbidden)
    end

    # GET /api/interviews/:id/next_question
    def next_question
      unless @interview.in_progress?
        return render_api_error('Interview not in progress', status: :bad_request)
      end

      selector = InterviewEngine::QuestionSelector.new(@interview)

      unless selector.should_continue_interview?
        return render json: {
          success: true,
          message: 'All questions answered',
          interview_complete: true
        }
      end

      question = selector.get_next_question
      language = params[:language].presence || @interview.language || 'en'
      audio_data = selector.prepare_question_audio(question, language: language)

      @interview.touch_activity!

      render json: {
        success: true,
        question: audio_data,
        remaining_seconds: @interview.remaining_seconds
      }
    end

    # POST /api/interviews/:id/submit_answer
    def submit_answer
      question_id = params[:question_id]
      audio_file = params[:audio_file]
      video_file = params[:video_file]
      text_answer = params[:text_answer].presence || params[:selected_option].presence

      unless question_id && (audio_file || video_file || text_answer.present?)
        return render_api_error('Missing question_id or answer input', status: :bad_request)
      end

      # ファイルアップロードバリデーション
      validate_audio_upload!(audio_file)
      validate_video_upload!(video_file)

      question = Question.find_by(id: question_id, situation_id: @interview.situation_id)
      unless question
        return render_api_error('Question not found', status: :not_found)
      end

      # 二重回答防止: interviewレコードをロックして重複チェック
      @interview.with_lock do
        existing_response = @interview.interview_responses.find_by(question_id: question_id)
        if existing_response
          render_api_error('Question already answered', status: :conflict)
          return
        end
      end

      # ロック外で音声処理を実行（長時間処理のためロック外で行う）
      audio_service = InterviewEngine::AudioInterviewService.new(@interview)
      @_extracted_audio_path = nil
      media_result = audio_service.process_answer_media(
        audio_file: audio_file,
        video_file: video_file,
        text_answer: text_answer
      )
      @_extracted_audio_path = media_result[:extracted_audio_path]

      response = @interview.interview_responses.create!(
        question: question,
        audio_transcript: media_result[:transcript],
        evaluation_status: :pending
      )

      attach_media(response, audio_file, video_file, media_result[:extracted_audio_path])

      EvaluateInterviewResponseJob.perform_later(response.id)
      @interview.touch_activity!

      render json: {
        success: true,
        message: 'Response submitted for evaluation',
        response_id: response.id,
        remaining_seconds: @interview.remaining_seconds
      }, status: :created
    rescue InterviewEngine::AudioInterviewService::AudioError,
           InterviewEngine::STTClient::STTError,
           InterviewEngine::MediaProcessor::MediaError => e
      render_api_error(e.message, status: :bad_request)
    ensure
      # 例外時でも一時ファイルをクリーンアップ
      if @_extracted_audio_path
        InterviewEngine::AudioInterviewService.new(@interview).cleanup_temp_files(@_extracted_audio_path)
      end
    end

    # POST /api/interviews/:id/complete
    def complete
      unless @interview.in_progress?
        return render_api_error('Interview not in progress', status: :bad_request)
      end

      session_manager = InterviewEngine::SessionManager.new(@interview.user, @interview.situation)
      result = session_manager.complete_interview(@interview.id)

      @interview.reload

      render json: {
        success: true,
        message: 'Interview completed',
        result: {
          interview_id: @interview.id,
          final_status: result.final_status,
          average_score: result.results_data&.dig('average_score'),
          passing_score: result.results_data&.dig('passing_score'),
          total_questions: result.results_data&.dig('total_questions'),
          answered_questions: result.results_data&.dig('answered_questions'),
          rejected: @interview.rejected?,
          rejection_reason: @interview.rejection_reason
        }
      }
    rescue InterviewEngine::SessionManager::SessionError => e
      render_api_error(e.message, status: :unprocessable_entity)
    end

    # GET /api/interviews/:id/status
    def status
      session_manager = InterviewEngine::SessionManager.new(@interview.user, @interview.situation)
      state = session_manager.get_interview_state(@interview.id)

      state_with_rejection = state.merge(
        language: @interview.language,
        rejected: @interview.rejected?,
        rejection_reason: @interview.rejection_reason
      )

      render json: {
        success: true,
        state: state_with_rejection
      }
    end

    private

    # Content-Type検証（JSON/multipart以外を拒否）
    def verify_content_type!
      return if request.content_type.blank? # GETリクエスト等

      allowed = ['application/json', 'multipart/form-data']
      content_type = request.content_type&.split(';')&.first
      unless allowed.include?(content_type)
        render_api_error(
          "Unsupported Content-Type: #{content_type}",
          status: :unsupported_media_type
        )
      end
    end

    # トークン or APIキー or Devise認証の統合
    def authenticate_by_token_or_user!
      # ヘッダーまたはパラメータからトークン取得
      token = request.headers['X-Interview-Token'] || params[:access_token]

      if token.present?
        interview = Interview.by_token(token).first
        if interview
          @current_user = interview.user
          return
        end
      end

      # APIキー認証（Bearer token or X-API-Key ヘッダー）
      # APIキーが提示された場合は成否に関わらずここで完結（Deviseに落ちない）
      if extract_api_key.present?
        authenticate_by_api_key!
        return
      end

      # テストモード
      if test_mode?
        @current_user = User.find_by(email: 'test@interview.com') || User.first
        return
      end

      # Devise認証にフォールバック
      authenticate_user!
      @current_user = current_user
    end

    # APIキーによる認証
    def authenticate_by_api_key!
      api_key = extract_api_key

      configured_key = ENV['INTERVIEW_API_KEY']
      if configured_key.blank?
        render_api_error('API key authentication is not configured', status: :service_unavailable)
        return
      end

      unless ActiveSupport::SecurityUtils.secure_compare(api_key, configured_key)
        render_api_error('Invalid API key', status: :unauthorized)
        return
      end

      # APIキー認証時はデフォルトAPIユーザーを使用
      @current_user = User.find_by(email: 'api@interview.com') || User.first

      unless @current_user
        render_api_error('No user found. Create a user first.', status: :unprocessable_entity)
      end
    end

    # start用: 認証済みユーザーがいればそのまま、いなければゲストユーザーを割り当て
    def authenticate_or_create_guest!
      # 既存の認証手段を試行（トークン、APIキー、テストモード、Devise）
      token = request.headers['X-Interview-Token'] || params[:access_token]
      if token.present?
        interview = Interview.by_token(token).first
        if interview
          @current_user = interview.user
          return
        end
      end

      if extract_api_key.present?
        authenticate_by_api_key!
        return
      end

      if test_mode?
        @current_user = User.find_by(email: 'test@interview.com') || User.first
        return
      end

      # Deviseセッションがあればそれを使用
      if user_signed_in?
        @current_user = current_user
        return
      end

      # 未認証ユーザーにはゲストユーザーを割り当て（存在しなければ自動作成）
      @current_user = User.find_or_create_by(email: 'guest@interview.com') do |u|
        u.name = 'Guest'
        u.password = SecureRandom.hex(16)
      end
    end

    # Authorization: Bearer <key> または X-API-Key ヘッダーからAPIキーを抽出
    def extract_api_key
      auth_header = request.headers['Authorization']
      if auth_header&.start_with?('Bearer ')
        return auth_header.sub('Bearer ', '')
      end

      request.headers['X-API-Key']
    end

    def set_interview
      @interview = Interview.find_by(id: params[:id])
      unless @interview
        render_api_error('Interview not found', status: :not_found)
        return
      end
      authorize_interview!
    end

    # 操作前のタイムアウトチェック
    def check_session_timeout!
      return unless @interview&.in_progress?

      if @interview.timed_out?
        @interview.abandon!
        render_api_error(
          'Interview session has timed out',
          status: :gone,
          reason: 'timeout',
          details: { resumable: @interview.resumable? }
        )
      end
    end

    def test_mode?
      return false if Rails.env.production?
      ENV['AI_INTERVIEW_TEST_MODE'] == 'true'
    end

    def authorize_interview!
      return if test_mode?

      token = request.headers['X-Interview-Token'] || params[:access_token]
      if token.present?
        # トークンが提供された場合はトークンの一致/不一致で完結させる
        if @interview.access_token.present? &&
           ActiveSupport::SecurityUtils.secure_compare(token, @interview.access_token)
          return
        else
          render_api_error('Unauthorized', status: :forbidden)
          return
        end
      end

      unless @current_user && @interview.user_id == @current_user.id
        render_api_error('Unauthorized', status: :forbidden)
      end
    end

    def attach_media(response, audio_file, video_file, extracted_audio_path)
      if audio_file
        response.answer_audio.attach(audio_file)
      elsif extracted_audio_path
        File.open(extracted_audio_path, 'rb') do |file|
          response.answer_audio.attach(
            io: file,
            filename: File.basename(extracted_audio_path),
            content_type: 'audio/wav'
          )
        end
      end

      response.answer_video.attach(video_file) if video_file
    end
  end
end
