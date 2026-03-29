# frozen_string_literal: true

# アップロードファイルのサイズ・Content-Type検証
module FileUploadValidation
  extend ActiveSupport::Concern

  AUDIO_CONTENT_TYPES = %w[
    audio/mpeg audio/mp3 audio/mp4 audio/wav audio/webm
    audio/x-wav audio/x-m4a audio/ogg
  ].freeze

  VIDEO_CONTENT_TYPES = %w[
    video/mp4 video/webm video/quicktime video/x-msvideo
  ].freeze

  private

  def validate_audio_upload!(file)
    return unless file
    max_size = Rails.application.config.interview.max_audio_size
    validate_upload!(file, allowed_types: AUDIO_CONTENT_TYPES, max_size: max_size, label: 'Audio')
  end

  def validate_video_upload!(file)
    return unless file
    max_size = Rails.application.config.interview.max_video_size
    validate_upload!(file, allowed_types: VIDEO_CONTENT_TYPES, max_size: max_size, label: 'Video')
  end

  # マジックバイトによるファイル種別検証用マッピング
  MAGIC_BYTES = {
    'audio/mpeg'  => ["\xFF\xFB", "\xFF\xF3", "\xFF\xF2", "ID3"].map(&:b),
    'audio/wav'   => ["RIFF".b],
    'audio/x-wav' => ["RIFF".b],
    'audio/ogg'   => ["OggS".b],
    'video/mp4'   => ["ftyp".b],
    'audio/mp4'   => ["ftyp".b],
    'audio/x-m4a' => ["ftyp".b],
    'audio/mp3'   => ["\xFF\xFB", "\xFF\xF3", "\xFF\xF2", "ID3"].map(&:b),
    'audio/webm'  => ["\x1A\x45\xDF\xA3".b],
    'video/webm'  => ["\x1A\x45\xDF\xA3".b],
  }.freeze

  def validate_upload!(file, allowed_types:, max_size:, label:)
    unless file.respond_to?(:content_type)
      raise ActionController::BadRequest, "#{label} file is invalid"
    end

    unless allowed_types.include?(file.content_type)
      raise ActionController::BadRequest,
        "#{label} file type '#{file.content_type}' not allowed. Accepted: #{allowed_types.join(', ')}"
    end

    # マジックバイト検証（Content-Type偽造対策）
    validate_magic_bytes!(file, label: label)

    if file.size > max_size
      raise ActionController::BadRequest,
        "#{label} file too large (#{(file.size.to_f / 1024 / 1024).round(1)}MB, max #{max_size / 1024 / 1024}MB)"
    end
  end

  def validate_magic_bytes!(file, label:)
    return unless file.respond_to?(:read)

    header = file.read(12)
    file.rewind

    return if header.nil? || header.empty?

    content_type = file.content_type
    expected_signatures = MAGIC_BYTES[content_type]
    return unless expected_signatures # 未登録のContent-Typeはスキップ

    matched = expected_signatures.any? do |sig|
      # ftypはオフセット4から始まる
      if sig == "ftyp".b
        header.byteslice(4, 4)&.start_with?(sig)
      else
        header.start_with?(sig)
      end
    end

    unless matched
      raise ActionController::BadRequest,
        "#{label} file content does not match declared type '#{content_type}'"
    end
  end
end
