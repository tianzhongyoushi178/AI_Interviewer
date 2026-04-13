# frozen_string_literal: true

# 起動時にAI面接システムに必要なAPIキー・環境変数の存在を検証する
Rails.application.config.after_initialize do
  next if Rails.env.test?

  required_keys = {
    'OPENAI_API_KEY' => 'OpenAI (LLM評価/STT/TTS)'
  }

  # 本番環境で追加で必須となるキー
  if Rails.env.production?
    required_keys.merge!(
      'DATABASE_URL' => 'PostgreSQL接続URL（または DB_HOST/DB_NAME/DB_USERNAME/DB_PASSWORD を個別設定）',
      'RAILS_MASTER_KEY' => 'Rails暗号化キー'
    )
    # DATABASE_URLの代わりに個別設定がある場合はOK
    if ENV['DB_HOST'].present? && ENV['DB_NAME'].present?
      required_keys.delete('DATABASE_URL')
    end
    # RAILS_MASTER_KEYはconfig/master.keyがあればOK
    if File.exist?(Rails.root.join('config', 'master.key'))
      required_keys.delete('RAILS_MASTER_KEY')
    end
  end

  optional_keys = {
    'CLAUDE_API_KEY' => 'Claude (LLM評価/要約)',
    'INTERVIEW_API_KEY' => 'API認証キー（curl/外部クライアント用）',
    'REDIS_URL' => 'Redis（Sidekiqバックグラウンドジョブ）'
  }

  missing = required_keys.select { |key, _| ENV[key].blank? }

  if missing.any?
    missing.each do |key, service|
      Rails.logger.warn("[APIキー検証] WARNING: #{key} が未設定です。#{service} は動作しません。")
    end

    if Rails.env.production?
      raise "[APIキー検証] 本番環境で必須キーが未設定: #{missing.keys.join(', ')}"
    end
  end

  missing_optional = optional_keys.select { |key, _| ENV[key].blank? }
  missing_optional.each do |key, service|
    Rails.logger.warn("[APIキー検証] OPTIONAL: #{key} が未設定です。#{service} の機能は無効になります。")
  end

  # 本番でテストモードが有効な場合は警告
  if Rails.env.production? && ENV['AI_INTERVIEW_TEST_MODE'] == 'true'
    Rails.logger.error("[セキュリティ警告] 本番環境で AI_INTERVIEW_TEST_MODE=true が設定されています！認証がバイパスされます。")
    raise "[セキュリティ警告] 本番環境でテストモードは使用できません"
  end
end
