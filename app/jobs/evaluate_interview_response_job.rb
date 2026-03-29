# app/jobs/evaluate_interview_response_job.rb
class EvaluateInterviewResponseJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(interview_response_id)
    response = InterviewResponse.find(interview_response_id)

    # べき等性チェック: 既に評価済みの場合はスキップ
    return if response.completed?

    language = response.interview.situation.language || 'en'

    evaluator = InterviewEngine::ResponseEvaluator.new(response, language: language)
    evaluator.evaluate
  end
end
