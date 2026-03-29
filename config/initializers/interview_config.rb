# config/initializers/interview_config.rb
# AI面接システムの設定値を環境変数から一元管理する

Rails.application.config.interview = ActiveSupport::OrderedOptions.new

cfg = Rails.application.config.interview

# === LLM 設定 ===
cfg.llm_model          = ENV.fetch('LLM_MODEL', 'openai')             # openai / claude
cfg.openai_model       = ENV.fetch('OPENAI_MODEL', 'gpt-4o')          # OpenAI モデル名（gpt-4oはresponse_format: json_object対応）
cfg.claude_model       = ENV.fetch('CLAUDE_MODEL', 'claude-sonnet-4-20250514')
cfg.llm_temperature    = ENV.fetch('LLM_TEMPERATURE', '0.2').to_f
cfg.llm_max_tokens     = ENV.fetch('LLM_MAX_TOKENS', '600').to_i
cfg.llm_max_retries    = ENV.fetch('LLM_MAX_RETRIES', '3').to_i
cfg.llm_request_timeout = ENV.fetch('LLM_REQUEST_TIMEOUT', '30').to_i

# === STT (Speech-to-Text) 設定 ===
cfg.stt_model          = ENV.fetch('STT_MODEL', 'whisper-1')
cfg.stt_max_file_size  = ENV.fetch('STT_MAX_FILE_SIZE_MB', '25').to_i * 1024 * 1024
cfg.stt_max_retries    = ENV.fetch('STT_MAX_RETRIES', '2').to_i
cfg.stt_timeout        = ENV.fetch('STT_TIMEOUT', '60').to_i

# === TTS (Text-to-Speech) 設定 ===
cfg.tts_model          = ENV.fetch('TTS_MODEL', 'tts-1')
cfg.tts_max_text_length = ENV.fetch('TTS_MAX_TEXT_LENGTH', '4096').to_i
cfg.tts_max_retries    = ENV.fetch('TTS_MAX_RETRIES', '2').to_i
cfg.tts_timeout        = ENV.fetch('TTS_TIMEOUT', '30').to_i
cfg.tts_default_voice  = ENV.fetch('TTS_DEFAULT_VOICE', 'nova')
cfg.tts_voice_ja       = ENV.fetch('TTS_VOICE_JA', 'nova')
cfg.tts_voice_en       = ENV.fetch('TTS_VOICE_EN', 'nova')

# === メディア処理 設定 ===
cfg.max_video_size     = ENV.fetch('MAX_VIDEO_SIZE_MB', '500').to_i * 1024 * 1024
cfg.max_audio_size     = ENV.fetch('MAX_AUDIO_SIZE_MB', '25').to_i * 1024 * 1024
cfg.ffmpeg_timeout     = ENV.fetch('FFMPEG_TIMEOUT', '120').to_i
cfg.min_audio_duration = ENV.fetch('MIN_AUDIO_DURATION', '0.5').to_f
cfg.max_audio_duration = ENV.fetch('MAX_AUDIO_DURATION', '600').to_f

# === 評価設定 ===
cfg.default_pass_threshold = ENV.fetch('DEFAULT_PASS_THRESHOLD', '70').to_i
cfg.eval_weight_relevance  = ENV.fetch('EVAL_WEIGHT_RELEVANCE', '0.4').to_f
cfg.eval_weight_correctness = ENV.fetch('EVAL_WEIGHT_CORRECTNESS', '0.4').to_f
cfg.eval_weight_clarity    = ENV.fetch('EVAL_WEIGHT_CLARITY', '0.2').to_f
