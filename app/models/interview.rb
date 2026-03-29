# app/models/interview.rb
class Interview < ApplicationRecord
  belongs_to :user
  belongs_to :situation
  has_many :interview_responses, dependent: :destroy
  has_one :interview_result, dependent: :destroy

  enum status: {
    not_started: 0,
    in_progress: 1,
    completed: 2,
    failed: 3,
    abandoned: 4
  }

  enum language: {
    en: 'en',
    ja: 'ja'
  }

  validates :user_id, :situation_id, :language, presence: true
  validates :user_id, uniqueness: { scope: :situation_id, message: "can only interview once per situation" }
  validates :access_token, uniqueness: true, allow_nil: true

  # Business Rules
  validate :ensure_no_previous_interview, on: :create
  validate :ensure_situation_has_questions, on: :create
  validate :valid_status_transition, if: :status_changed?

  VALID_TRANSITIONS = {
    not_started: [:in_progress],
    in_progress: [:completed, :failed, :abandoned],
    abandoned: [:in_progress],
    completed: [],
    failed: []
  }.freeze

  before_create :generate_access_token

  scope :by_user_and_situation, ->(user, situation) { where(user: user, situation: situation) }
  scope :completed_or_failed, -> { where(status: [:completed, :failed]) }
  scope :by_token, ->(token) { where(access_token: token) }
  # NOTE: timed_out判定はSQLite固有構文を避けるためRuby側(timed_out?)で行う

  def start!
    update!(status: :in_progress, started_at: Time.current, last_activity_at: Time.current)
  end

  def complete!
    update!(status: :completed, ended_at: Time.current)
  end

  def fail!
    update!(status: :failed, ended_at: Time.current)
  end

  def abandon!
    update!(status: :abandoned, ended_at: Time.current)
  end

  # セッションアクティビティを記録
  def touch_activity!
    update!(last_activity_at: Time.current)
  end

  # タイムアウト判定
  def timed_out?
    return false unless in_progress? && last_activity_at.present?

    timeout = situation.session_timeout_minutes.minutes
    last_activity_at < timeout.ago
  end

  # 中断復帰が可能か判定
  def resumable?
    return false unless abandoned? || (in_progress? && timed_out?)
    return false unless situation.allow_resume?
    return false if resume_count >= situation.max_resume_count

    true
  end

  # 面接を再開（同時リクエスト対策として悲観ロック使用）
  def resume!
    with_lock do
      raise "Interview cannot be resumed" unless resumable?

      update!(
        status: :in_progress,
        resumed_at: Time.current,
        last_activity_at: Time.current,
        resume_count: resume_count + 1,
        ended_at: nil
      )
    end
  end

  def rejected?
    rejection_reason.present? && rejected_at.present?
  end

  def duration
    return nil unless started_at && ended_at
    (ended_at - started_at).to_i
  end

  def answered_question_count
    interview_responses.count
  end

  def total_questions
    situation.questions.count
  end

  def progress_percentage
    return 0 if total_questions.zero?
    ((answered_question_count.to_f / total_questions) * 100).round(2)
  end

  # 残り時間（秒）
  def remaining_seconds
    return nil unless in_progress? && last_activity_at.present?

    timeout = situation.session_timeout_minutes.minutes
    elapsed = Time.current - last_activity_at
    remaining = timeout - elapsed
    [remaining.to_i, 0].max
  end

  private

  def generate_access_token
    self.access_token = loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless Interview.exists?(access_token: token)
    end
  end

  def ensure_no_previous_interview
    existing = Interview.by_user_and_situation(user, situation).completed_or_failed.exists?
    errors.add(:base, "User has already completed this interview") if existing
  end

  def ensure_situation_has_questions
    return if situation.nil?
    errors.add(:situation, "must have at least 1 question") if situation.questions.empty?
  end

  def valid_status_transition
    from = status_was&.to_sym
    to = status&.to_sym
    return if from.nil?
    unless VALID_TRANSITIONS[from]&.include?(to)
      errors.add(:status, "cannot transition from #{from} to #{to}")
    end
  end
end
