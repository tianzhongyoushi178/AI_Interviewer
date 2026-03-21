# app/models/interview_result.rb
class InterviewResult < ApplicationRecord
  belongs_to :interview

  enum final_status: {
    passed: 0,
    failed: 1,
    incomplete: 2
  }

  validates :interview_id, presence: true, uniqueness: true

  # Store comprehensive results as JSON
  store :results_data, accessors: [
    :total_questions,
    :answered_questions,
    :skipped_questions,
    :average_score,
    :responses_summary,
    :summary,
    :conversation_log,
    :strengths,
    :weaknesses,
    :recommendation
  ], coder: JSON

  # rejection_details はJSONカラムとして直接アクセスする
  # store を使わないことで、prefix による accessor 不整合を防ぐ

  def completion_percentage
    return 0 if total_questions.to_i.zero?
    ((answered_questions.to_i.to_f / total_questions.to_i) * 100).round(2)
  end

  def rejected?
    details = rejection_details
    return false if details.blank?

    parsed = details.is_a?(String) ? (JSON.parse(details) rescue nil) : details
    parsed.is_a?(Hash) && parsed.any?
  end
end
