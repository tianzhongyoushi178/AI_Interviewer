# app/models/interview_response.rb
class InterviewResponse < ApplicationRecord
  belongs_to :interview
  belongs_to :question
  has_one_attached :answer_audio
  has_one_attached :answer_video

  enum evaluation_status: {
    pending: 0,
    evaluating: 1,
    completed: 2,
    failed: 3
  }

  validates :interview_id, :question_id, presence: true
  validates :audio_transcript, presence: true
  validate :question_belongs_to_interview_situation

  # Store evaluation results
  store :evaluation_data, accessors: [
    :relevance_score,
    :correctness_score,
    :clarity_score,
    :final_score,
    :evaluation_feedback,
    :passed,
    :ai_reasoning
  ], coder: JSON

  scope :in_order, -> { joins(:question).order('"questions"."order" ASC') }
  scope :evaluated, -> { where.not(evaluation_status: :pending) }
  scope :passed_evaluation, -> {
    adapter = ActiveRecord::Base.connection.adapter_name
    if adapter == 'PostgreSQL'
      where("(evaluation_data->>'passed')::boolean = true")
    else
      where("json_extract(evaluation_data, '$.passed') = 1")
    end
  }

  def evaluated?
    completed?
  end

  def passed_evaluation?
    evaluation_data&.dig('passed') == true
  end

  def score
    evaluation_data&.dig('final_score')&.to_f
  end

  private

  def question_belongs_to_interview_situation
    return if interview.nil? || question.nil?

    unless question.situation_id == interview.situation_id
      errors.add(:question, "はこの面接のシチュエーションに属していません")
    end
  end
end
