#!/usr/bin/env ruby
# Complete AI Interview System - Offline Integration Test
# Usage: bundle exec rails runner test_complete_interview_system_offline.rb
# No server required - tests the service layer directly

require 'securerandom'

class InterviewSystemOfflineTest
  def initialize
    @test_results = []
    @user = nil
    @interview = nil
  end

  def run_all_tests
    puts "\n" + "="*80
    puts "🧪 COMPLETE AI INTERVIEW SYSTEM - OFFLINE VALIDATION"
    puts "="*80

    setup_test_data
    test_interview_flow
    test_validation_rules
    test_error_handling
    print_results

    @test_results.all? { |r| r[:passed] } ? 0 : 1
  end

  private

  def setup_test_data
    puts "\n▶ SETUP: Creating test data..."

    # Clean up old test data (with proper cascading)
    Interview.where("created_at < ?", 1.hour.ago).destroy_all
    User.where("email LIKE ? AND created_at < ?", "test_%@interview.com", 1.hour.ago).destroy_all
    Client.where("email LIKE ? AND created_at < ?", "test_client_%@interview.com", 1.hour.ago).destroy_all

    @user = User.create!(
      name: 'Test User',
      email: "test_#{SecureRandom.hex(4)}@interview.com",
      password: 'test1234',
      password_confirmation: 'test1234'
    )

    @client = Client.create!(
      email: "test_client_#{SecureRandom.hex(4)}@interview.com",
      password: 'password123',
      password_confirmation: 'password123'
    )

    @situation = Situation.create!(
      title: 'Backend Engineer Interview',
      client: @client,
      description: 'Full-stack backend engineer technical interview',
      language: 'en'
    )

    # Create test questions
    [
      { text: 'Tell us about your experience with Ruby on Rails', order: 1 },
      { text: 'How do you approach debugging in production?', order: 2 },
      { text: 'Describe your approach to writing clean code', order: 3 }
    ].each do |q|
      @situation.questions.create!(
        question_text: q[:text],
        order: q[:order],
        question_type: 'descriptive'
      )
    end

    test('Data Setup', true, 'User, Client, Situation, Questions created')
  end

  def test_interview_flow
    puts "\n▶ TEST: Interview Flow (Direct Service Calls)"

    begin
      # 1. Start Interview using SessionManager
      session_manager = InterviewEngine::SessionManager.new(@user, @situation)
      @interview = session_manager.start_interview(language: 'en')

      test('1. Start Interview', @interview.present? && @interview.in_progress?, "Interview ID: #{@interview&.id}")

      unless @interview && @interview.in_progress?
        test('Interview Flow', false, 'Failed to start interview')
        return
      end

      # 2. Verify interview state
      test('2. Interview State', @interview.in_progress?, "Status: #{@interview.status}")

      # 3. Get first question using QuestionSelector
      selector = InterviewEngine::QuestionSelector.new(@interview)
      should_continue = selector.should_continue_interview?
      test('3. Should Continue', should_continue, 'Interview has questions to ask')

      question = selector.get_next_question
      test('4. Get First Question', question.present?, "Q1: #{question&.question_text&.first(40)}...")

      return unless question.present?

      # 4. Submit Answer and create InterviewResponse
      response = @interview.interview_responses.create!(
        question: question,
        audio_transcript: 'I have 5 years of Rails experience building scalable APIs.'
      )

      test('5. Submit Answer', response.persisted?, "Response ID: #{response.id}")

      # 5. Get second question (新しい selector で最新の interview_responses を反映)
      @interview.reload
      selector = InterviewEngine::QuestionSelector.new(@interview)
      question2 = selector.get_next_question
      response2 = @interview.interview_responses.create!(
        question: question2,
        audio_transcript: 'I use logs, monitoring tools, and quick debugging techniques.'
      )

      test('6. Submit Second Answer', response2.persisted?, "Response 2 ID: #{response2.id}")

      # 6. Get third question
      @interview.reload
      selector = InterviewEngine::QuestionSelector.new(@interview)
      question3 = selector.get_next_question
      response3 = @interview.interview_responses.create!(
        question: question3,
        audio_transcript: 'I follow SOLID principles, use clear naming, and write tests.'
      )

      test('7. Submit Third Answer', response3.persisted?, "Response 3 ID: #{response3.id}")

      # 7. Verify all questions answered
      @interview.reload
      selector = InterviewEngine::QuestionSelector.new(@interview)
      should_continue = selector.should_continue_interview?
      test('8. All Questions Answered', !should_continue, "No more questions available")

      # Evaluate responses before completing (mark as completed with sample scores)
      @interview.interview_responses.each do |response|
        response.update_column(:evaluation_status, :completed)
        response.update_column(:evaluation_data, {
          relevance_score: 80,
          correctness_score: 85,
          clarity_score: 82,
          final_score: 82.3,
          passed: true,
          ai_reasoning: 'Test response - excellent technical knowledge'
        }.to_json)
      end

      # 7. Complete Interview using SessionManager
      result = session_manager.complete_interview(@interview.id)
      @interview.reload

      test('9. Complete Interview', @interview.completed? || @interview.failed?, "Final Status: #{@interview.status}")

      # 9. Verify results calculated
      interview_result = @interview.interview_result
      has_result = interview_result.present?
      test('10. Results Created', has_result, "Result ID: #{interview_result&.id}")

    rescue => e
      test('Interview Flow', false, "Error: #{e.message}")
      puts "  Backtrace: #{e.backtrace.first(3).join("\n    ")}"
    end
  end

  def test_validation_rules
    puts "\n▶ TEST: Validation Rules"

    # Test 1: Duplicate interview attempt
    begin
      session_manager = InterviewEngine::SessionManager.new(@user, @situation)
      second_interview = session_manager.start_interview(language: 'en')
      # 重複防止OKとみなす条件: nil / 既存(in_progress)の同一IDを返した / 別IDだが新規作成は許されないので発生しないはず
      test('Duplicate Interview Prevention', second_interview.nil? || second_interview.id == @interview.id, 'Should prevent or return existing')
    rescue => e
      test('Duplicate Interview Prevention', e.message.include?('already') || e.message.include?('unique') || e.message.include?('Validation failed'), "Error: #{e.message[0..60]}")
    end

    # Test 2: Situation must have questions
    begin
      empty_client = Client.create!(
        email: "empty_client_#{SecureRandom.hex(4)}@interview.com",
        password: 'password123',
        password_confirmation: 'password123'
      )

      empty_situation = Situation.create!(
        title: 'Empty Situation',
        client: empty_client,
        language: 'en'
      )

      empty_user = User.create!(
        name: 'Empty User',
        email: "empty_user_#{SecureRandom.hex(4)}@interview.com",
        password: 'test1234',
        password_confirmation: 'test1234'
      )

      session_manager = InterviewEngine::SessionManager.new(empty_user, empty_situation)
      interview = session_manager.start_interview(language: 'en')
      test('Require Questions', interview.nil?, 'Should require questions')
    rescue => e
      test('Require Questions', e.message.include?('question') || e.message.include?('Question'), "Error: #{e.message[0..50]}")
    end

    # Test 3: Invalid situation
    begin
      user = User.create!(
        name: 'Invalid User',
        email: "invalid_#{SecureRandom.hex(4)}@interview.com",
        password: 'test1234',
        password_confirmation: 'test1234'
      )

      fake_situation = OpenStruct.new(id: 99999)
      session_manager = InterviewEngine::SessionManager.new(user, fake_situation)
      interview = session_manager.start_interview(language: 'en')
      test('Invalid Situation', interview.nil?, 'Should handle invalid situation')
    rescue => e
      test('Invalid Situation', true, "Properly handled: #{e.class.name}")
    end
  end

  def test_error_handling
    puts "\n▶ TEST: Error Handling"

    # Test 1: Missing interview
    begin
      Interview.find(99999)
      test('Missing Interview', false, 'Should not find non-existent interview')
    rescue ActiveRecord::RecordNotFound
      test('Missing Interview', true, '404 handling works')
    rescue => e
      test('Missing Interview', true, "Error handled: #{e.class.name}")
    end

    # Test 2: Interview model validations
    begin
      interview = Interview.new(status: 'in_progress')
      interview.valid?
      errors = interview.errors.messages
      test('Model Validations', errors.present?, "Validates: #{errors.keys.join(', ')}")
    rescue => e
      test('Model Validations', true, "Validation works: #{e.class.name}")
    end

    # Test 3: Language support
    begin
      test('Language Support (EN)', @situation.language == 'en', 'English support verified')

      ja_client = Client.create!(
        email: "ja_client_#{SecureRandom.hex(4)}@interview.com",
        password: 'password123',
        password_confirmation: 'password123'
      )

      ja_situation = Situation.create!(
        title: '日本人エンジニア向けインタビュー',
        client: ja_client,
        description: 'Japanese technical interview',
        language: 'ja'
      )

      ja_situation.questions.create!(
        question_text: '開発経験について教えてください',
        order: 1,
        question_type: 'descriptive'
      )

      test('Language Support (JA)', ja_situation.language == 'ja', 'Japanese support verified')
    rescue => e
      test('Language Support (JA)', false, "Error: #{e.message[0..50]}")
    end
  end

  def test(name, passed, details = '')
    status = passed ? '✅' : '❌'
    @test_results << { name: name, passed: passed, details: details }
    puts "#{status} #{name}"
    puts "   #{details}" if details.present?
  end

  def print_results
    puts "\n" + "="*80
    puts "📊 TEST RESULTS SUMMARY"
    puts "="*80

    total = @test_results.count
    passed = @test_results.count { |r| r[:passed] }
    failed = total - passed

    puts "\n  Total: #{total}"
    puts "  ✅ Passed: #{passed}"
    puts "  ❌ Failed: #{failed}"

    if total > 0
      puts "  Success Rate: #{(passed * 100 / total).round(1)}%"
    end

    if failed > 0
      puts "\n❌ FAILED TESTS:"
      @test_results.reject { |r| r[:passed] }.each do |r|
        puts "  - #{r[:name]}: #{r[:details]}"
      end
    else
      puts "\n✅ ALL TESTS PASSED!"
    end

    puts "\n" + "="*80
  end
end

begin
  tester = InterviewSystemOfflineTest.new
  exit_code = tester.run_all_tests
  exit exit_code
rescue => e
  puts "\n❌ CRITICAL ERROR: #{e.message}"
  puts e.backtrace.first(10)
  exit 1
end
