# Create test user
user = User.find_or_create_by(email: 'test@interview.com') do |u|
  u.name = 'Test User'
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "✅ User: #{user.email}"

# Create test client
client = Client.find_or_create_by(email: 'client@interview.com') do |c|
  c.password = 'password123'
  c.password_confirmation = 'password123'
end
puts "✅ Client: #{client.email}"

# Create situation
situation = Situation.find_or_create_by(title: 'Software Engineer Interview') do |s|
  s.client = client
  s.description = 'AI-powered interview for backend engineers'
  s.language = 'en'
end
puts "✅ Situation: #{situation.title} (ID: #{situation.id})"

# Create questions
questions_data = [
  { question_text: 'Tell us about your experience with Ruby on Rails', order: 1 },
  { question_text: 'How do you handle errors and debugging in production?', order: 2 },
  { question_text: 'Describe a challenging project you worked on', order: 3 }
]

questions_data.each do |q_data|
  Question.find_or_create_by(question_text: q_data[:question_text]) do |q|
    q.situation = situation
    q.question_type = 'long_answer'
    q.order = q_data[:order]
  end
end

puts "✅ Questions: #{situation.questions.count} created"

# Create guest user (ブラウザからの未認証面接用)
guest = User.find_or_create_by(email: 'guest@interview.com') do |u|
  u.name = 'Guest'
  u.password = SecureRandom.hex(16)
  u.password_confirmation = u.password
end
puts "✅ Guest User: #{guest.email}"
