# app/services/interview_engine/response_validator.rb
module InterviewEngine
  class ResponseValidator
    class InvalidResponseError < StandardError; end

    class << self
      # 評価レスポンスのバリデーション
      def validate_evaluation!(data)
        schema = PromptTemplate.expected_schema(:evaluation)
        validate_against_schema!(data, schema)
        clamp_scores!(data, schema)
        coerce_boolean!(data, 'passed')
        data
      end

      # サマリーレスポンスのバリデーション
      def validate_summary!(data)
        schema = PromptTemplate.expected_schema(:summary)
        validate_against_schema!(data, schema)
        truncate_arrays!(data, schema)
        data
      end

      # LLMレスポンスからJSONを安全に抽出
      def extract_json(raw_text)
        return nil if raw_text.blank?

        # まずそのままパースを試行
        parsed = try_parse(raw_text.strip)
        return parsed if parsed

        # ```json ... ``` ブロックを抽出
        code_block = raw_text.match(/```(?:json)?\s*([\s\S]*?)```/)
        if code_block
          parsed = try_parse(code_block[1].strip)
          return parsed if parsed
        end

        # { ... } を抽出（最も外側のブレース）
        begin
          json_match = Timeout.timeout(2) { raw_text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/) }
          if json_match
            parsed = try_parse(json_match[0])
            return parsed if parsed
          end
        rescue Timeout::Error
          Rails.logger.warn("ResponseValidator#extract_json: regex timed out, skipping brace extraction")
        end

        nil
      end

      private

      def try_parse(text)
        JSON.parse(text).with_indifferent_access
      rescue JSON::ParserError
        nil
      end

      def validate_against_schema!(data, schema)
        unless data.is_a?(Hash) || data.is_a?(ActiveSupport::HashWithIndifferentAccess)
          raise InvalidResponseError, "Response must be a Hash, got #{data.class}"
        end

        missing = schema[:required_keys].reject { |key| data.key?(key) }
        if missing.any?
          raise InvalidResponseError, "Missing required keys: #{missing.join(', ')}"
        end
      end

      # スコアを0-100範囲に制限
      def clamp_scores!(data, schema)
        return unless schema[:score_keys]

        range = schema[:score_range] || (0..100)

        schema[:score_keys].each do |key|
          value = data[key]
          numeric = value.to_f.round
          data[key] = numeric.clamp(range.min, range.max)
        end
      end

      # boolean値を型変換
      def coerce_boolean!(data, key)
        val = data[key]
        data[key] = case val
                    when true, 'true', 1 then true
                    when false, 'false', 0 then false
                    else false
                    end
      end

      # 配列項目数を制限
      def truncate_arrays!(data, schema)
        return unless schema[:array_keys]

        schema[:array_keys].each do |key|
          val = data[key]
          data[key] = if val.is_a?(Array)
                        val.first(5).map { |item| item.to_s.truncate(200) }
                      else
                        []
                      end
        end
      end
    end
  end
end
