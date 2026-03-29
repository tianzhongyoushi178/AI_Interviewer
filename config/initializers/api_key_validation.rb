# frozen_string_literal: true

# 起動時にAI面接システムに必要なAPIキーの存在を検証する
Rails.application.config.after_initialize do
  next if Rails.env.test?

  required_keys = {
    'OPENAI_API_KEY' => 'OpenAI (LLM評価/STT/TTS)'
  }

  optional_keys = {
    'CLAUDE_API_KEY' => 'Claude (LLM評価/要約)'
  }

  missing = required_keys.select { |key, _| ENV[key].blank? }

  if missing.any?
    missing.each do |key, service|
      Rails.logger.warn("[APIキー検証] WARNING: #{key} が未設定です。#{service} は動作しません。")
    end

    if Rails.env.production?
      raise "[APIキー検証] 本番環境で必須APIキーが未設定: #{missing.keys.join(', ')}"
    end
  end

  missing_optional = optional_keys.select { |key, _| ENV[key].blank? }
  missing_optional.each do |key, service|
    Rails.logger.warn("[APIキー検証] OPTIONAL: #{key} が未設定です。#{service} の機能は無効になります。")
  end
end
