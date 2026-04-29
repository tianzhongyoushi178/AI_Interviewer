# frozen_string_literal: true

redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # sidekiq-cron による定期ジョブのロード（serverプロセスでのみ）
  schedule_file = Rails.root.join('config/sidekiq_schedule.yml')
  if File.exist?(schedule_file)
    require 'sidekiq/cron/job'
    schedule = YAML.safe_load_file(schedule_file, permitted_classes: [Symbol], aliases: true)
    Sidekiq::Cron::Job.load_from_hash(schedule)
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
