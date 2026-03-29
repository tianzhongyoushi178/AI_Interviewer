# app/services/interview_engine/llm_client.rb
require 'net/http'
require 'json'

module InterviewEngine
  class LLMClient

    OPENAI_URL = 'https://api.openai.com/v1/chat/completions'
    CLAUDE_URL = 'https://api.anthropic.com/v1/messages'
    RETRY_DELAY_BASE = 1 # seconds (exponential backoff)

    # response_format: json_object をサポートするモデルのプレフィックス一覧
    # gpt-4-turbo 以降 および gpt-4o 系が対応
    JSON_OBJECT_SUPPORTED_MODELS = %w[gpt-4o gpt-4-turbo gpt-3.5-turbo].freeze

    def self.json_object_supported?(model_name)
      JSON_OBJECT_SUPPORTED_MODELS.any? { |prefix| model_name.start_with?(prefix) }
    end

    class LLMError < StandardError; end
    class LLMTimeoutError < LLMError; end
    class LLMResponseError < LLMError; end
    class LLMValidationError < LLMError; end

    def initialize(model: nil)
      @model = model || config.llm_model
    end

    # 回答評価（バリデーション・リトライ付き）
    def evaluate_response(question_text, user_answer, language: 'en', question_type: 'open')
      prompt = PromptTemplate.evaluation(
        question_text: question_text,
        user_answer: user_answer,
        language: language,
        question_type: question_type
      )

      result = call_with_retry(prompt, :evaluation)
      ResponseValidator.validate_evaluation!(result)
    rescue ResponseValidator::InvalidResponseError => e
      Rails.logger.error("LLM Evaluation Validation Error: #{e.message}")
      default_error_response
    rescue LLMError => e
      Rails.logger.error("LLM Evaluation Error: #{e.message}")
      default_error_response
    end

    # 面接サマリー生成（バリデーション・リトライ付き）
    def summarize_interview(responses, language: 'en')
      responses_data = responses.map do |r|
        {
          question: r.question.question_text,
          answer: r.audio_transcript,
          score: r.score
        }
      end

      prompt = PromptTemplate.summary(
        responses_data: responses_data,
        language: language
      )

      result = call_with_retry(prompt, :summary)
      ResponseValidator.validate_summary!(result)
    rescue ResponseValidator::InvalidResponseError => e
      Rails.logger.error("LLM Summary Validation Error: #{e.message}")
      default_summary_response
    rescue LLMError => e
      Rails.logger.error("LLM Summary Error: #{e.message}")
      default_summary_response
    end

    private

    # リトライ付きLLM呼び出し
    def call_with_retry(prompt, validation_type)
      last_error = nil

      config.llm_max_retries.times do |attempt|
        begin
          raw_response = call_llm(prompt)
          result = ResponseValidator.extract_json(raw_response)

          if result
            Rails.logger.info("LLM call succeeded on attempt #{attempt + 1}")
            return result
          end

          last_error = "Failed to extract valid JSON (attempt #{attempt + 1})"
          Rails.logger.warn(last_error)
        rescue LLMTimeoutError, LLMResponseError => e
          last_error = e.message
          Rails.logger.warn("LLM retryable error (attempt #{attempt + 1}): #{e.message}")
        end

        sleep(RETRY_DELAY_BASE ** (attempt + 1)) if attempt < config.llm_max_retries - 1
      end

      raise LLMValidationError, "All #{config.llm_max_retries} attempts failed: #{last_error}"
    end

    # LLM API呼び出し（モデル切替）
    def call_llm(prompt)
      case @model
      when 'openai'
        call_openai(prompt)
      when 'claude'
        call_claude(prompt)
      else
        raise LLMError, "Unknown model: #{@model}"
      end
    end

    # OpenAI API呼び出し
    def call_openai(prompt)
      api_key = ENV['OPENAI_API_KEY']
      raise LLMError, "OPENAI_API_KEY is not set" if api_key.blank?

      uri = URI(OPENAI_URL)
      http = build_http(uri)

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'

      body = {
        model: config.openai_model,
        messages: [
          { role: 'system', content: prompt[:system] },
          { role: 'user', content: prompt[:user] }
        ],
        temperature: config.llm_temperature,
        max_tokens: config.llm_max_tokens
      }

      if self.class.json_object_supported?(config.openai_model)
        body[:response_format] = { type: 'json_object' }
      end

      request.body = body.to_json
      response = http.request(request)

      handle_api_response(response, 'OpenAI')

      parsed = JSON.parse(response.body)
      content = parsed.dig('choices', 0, 'message', 'content')
      raise LLMResponseError, "Empty content from OpenAI" if content.blank?

      content
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise LLMTimeoutError, "OpenAI request timed out: #{e.message}"
    rescue JSON::ParserError => e
      raise LLMResponseError, "Failed to parse OpenAI response: #{e.message}"
    end

    # Claude API呼び出し
    def call_claude(prompt)
      api_key = ENV['CLAUDE_API_KEY']
      raise LLMError, "CLAUDE_API_KEY is not set" if api_key.blank?

      uri = URI(CLAUDE_URL)
      http = build_http(uri)

      request = Net::HTTP::Post.new(uri.path)
      request['x-api-key'] = api_key
      request['anthropic-version'] = '2023-06-01'
      request['Content-Type'] = 'application/json'

      body = {
        model: config.claude_model,
        max_tokens: config.llm_max_tokens,
        system: prompt[:system],
        messages: [
          { role: 'user', content: prompt[:user] }
        ]
      }

      request.body = body.to_json
      response = http.request(request)

      handle_api_response(response, 'Claude')

      parsed = JSON.parse(response.body)
      content = parsed.dig('content', 0, 'text')
      raise LLMResponseError, "Empty content from Claude" if content.blank?

      content
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise LLMTimeoutError, "Claude request timed out: #{e.message}"
    rescue JSON::ParserError => e
      raise LLMResponseError, "Failed to parse Claude response: #{e.message}"
    end

    # HTTP接続のビルド（タイムアウト設定付き）
    def build_http(uri)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = config.llm_request_timeout
      http.read_timeout = config.llm_request_timeout
      http
    end

    def config
      Rails.application.config.interview
    end

    # APIレスポンスのHTTPステータスチェック
    def handle_api_response(response, provider)
      case response.code.to_i
      when 200..299
        # OK
      when 429
        raise LLMResponseError, "#{provider} rate limit exceeded"
      when 401, 403
        raise LLMError, "#{provider} authentication failed (#{response.code})"
      when 500..599
        raise LLMResponseError, "#{provider} server error (#{response.code})"
      else
        raise LLMError, "#{provider} unexpected response (#{response.code}): #{response.body.truncate(200)}"
      end
    end

    def default_error_response
      {
        relevance_score: 0,
        correctness_score: 0,
        clarity_score: 0,
        final_score: 0,
        passed: false,
        reasoning: 'Evaluation failed - please retry'
      }.with_indifferent_access
    end

    def default_summary_response
      {
        summary: 'Summary unavailable',
        strengths: [],
        weaknesses: [],
        recommendation: 'Review required'
      }.with_indifferent_access
    end
  end
end
