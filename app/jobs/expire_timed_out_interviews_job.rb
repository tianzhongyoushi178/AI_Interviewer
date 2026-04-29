# frozen_string_literal: true

# 進行中(in_progress)で last_activity_at が situation の session_timeout_minutes を
# 超えた面接を abandoned にする定期ジョブ。
# sidekiq-cron で定期実行される（config/sidekiq_schedule.yml）。
class ExpireTimedOutInterviewsJob < ApplicationJob
  queue_as :default

  def perform
    InterviewEngine::SessionManager.expire_timed_out_sessions!
  end
end
