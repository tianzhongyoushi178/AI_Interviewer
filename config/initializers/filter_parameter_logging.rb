# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password,
  :access_token,
  :api_key,
  :openai_api_key,
  :claude_api_key,
  :interview_api_key,
  :token,
  :secret
]
