require 'rails_helper'
require 'open3'

RSpec.describe InterviewEngine::MediaProcessor do
  # ffmpeg_available キャッシュをリセット
  before do
    described_class.instance_variable_set(:@ffmpeg_available, nil)
  end

  describe '.extract_audio_from_video' do
    let(:video_path) { '/tmp/test_video.mp4' }
    let(:success_status) { instance_double(Process::Status, success?: true) }
    let(:failure_status) { instance_double(Process::Status, success?: false) }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(video_path).and_return(true)
      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(video_path).and_return(10_000_000)
      # ffmpegが利用可能
      allow(described_class).to receive(:system).and_return(true)
    end

    it '動画から音声を抽出してファイルパスを返す' do
      output_path = nil
      allow(Open3).to receive(:capture3) do |*args, **opts|
        output_path = args.last
        File.binwrite(output_path, 'fake_audio_data')
        ['', '', success_status]
      end

      result = described_class.extract_audio_from_video(video_path)

      expect(result).to be_a(String)
      expect(result).to end_with('.wav')
      expect(File.exist?(result)).to be true

      File.delete(result) if File.exist?(result)
    end

    it '存在しないファイルでMediaErrorを発生する' do
      allow(File).to receive(:exist?).with(video_path).and_return(false)

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /not found/)
    end

    it '空のファイルでMediaErrorを発生する' do
      allow(File).to receive(:size).with(video_path).and_return(0)

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /empty/)
    end

    it 'ファイルサイズ超過でMediaErrorを発生する' do
      max_size = Rails.application.config.interview.max_video_size
      allow(File).to receive(:size).with(video_path).and_return(max_size + 1)

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /too large/)
    end

    it 'ffmpeg未インストールでMediaErrorを発生する' do
      allow(described_class).to receive(:system).and_return(false)

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /ffmpeg is not installed/)
    end

    it 'ffmpeg失敗時にMediaErrorを発生する' do
      allow(Open3).to receive(:capture3) do |*args, **opts|
        output_path = args.last
        # 出力ファイルが作成されない（失敗ケース）
        ['', 'error output', failure_status]
      end

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /Failed to extract/)
    end

    it 'ffmpegタイムアウトでMediaErrorを発生する' do
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /timed out/)
    end

    it '抽出した音声が空の場合にMediaErrorを発生する' do
      allow(Open3).to receive(:capture3) do |*args, **opts|
        output_path = args.last
        FileUtils.touch(output_path) # 空ファイル作成
        ['', '', success_status]
      end

      expect {
        described_class.extract_audio_from_video(video_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /empty/)
    end
  end

  describe '.audio_duration' do
    let(:audio_path) { '/tmp/test_audio.wav' }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_path).and_return(true)
      allow(described_class).to receive(:system).and_return(true)
    end

    it '音声ファイルの長さを返す' do
      allow(Open3).to receive(:capture3).and_return(
        ["120.5\n", '', instance_double(Process::Status, success?: true)]
      )

      result = described_class.audio_duration(audio_path)
      expect(result).to eq(120.5)
    end

    it 'ファイルが存在しない場合にMediaErrorを発生する' do
      allow(File).to receive(:exist?).with(audio_path).and_return(false)

      expect {
        described_class.audio_duration(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /not found/)
    end

    it 'ffprobe失敗時にnilを返す' do
      allow(Open3).to receive(:capture3).and_return(
        ['', 'error', instance_double(Process::Status, success?: false)]
      )

      result = described_class.audio_duration(audio_path)
      expect(result).to be_nil
    end
  end

  describe '.validate_audio_duration!' do
    let(:audio_path) { '/tmp/test_audio.wav' }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_path).and_return(true)
      allow(described_class).to receive(:system).and_return(true)
    end

    it '正常な長さの音声は何もしない' do
      allow(described_class).to receive(:audio_duration).and_return(30.0)

      expect {
        described_class.validate_audio_duration!(audio_path)
      }.not_to raise_error
    end

    it '短すぎる音声でMediaErrorを発生する' do
      min = Rails.application.config.interview.min_audio_duration
      allow(described_class).to receive(:audio_duration).and_return(min - 0.1)

      expect {
        described_class.validate_audio_duration!(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /too short/)
    end

    it '長すぎる音声でMediaErrorを発生する' do
      max = Rails.application.config.interview.max_audio_duration
      allow(described_class).to receive(:audio_duration).and_return(max + 1)

      expect {
        described_class.validate_audio_duration!(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /too long/)
    end

    it 'ffprobeが使えない場合はスキップする' do
      allow(described_class).to receive(:audio_duration).and_return(nil)

      expect {
        described_class.validate_audio_duration!(audio_path)
      }.not_to raise_error
    end
  end

  describe '.normalize_audio' do
    let(:audio_path) { '/tmp/test_audio.wav' }
    let(:success_status) { instance_double(Process::Status, success?: true) }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(audio_path).and_return(true)
      allow(described_class).to receive(:system).and_return(true)
    end

    it '正規化した音声ファイルのパスを返す' do
      allow(Open3).to receive(:capture3) do |*args, **opts|
        output_path = args.last
        File.binwrite(output_path, 'normalized_audio_data')
        ['', '', success_status]
      end

      result = described_class.normalize_audio(audio_path)

      expect(result).to be_a(String)
      expect(result).to end_with('.wav')
      expect(File.exist?(result)).to be true

      File.delete(result) if File.exist?(result)
    end

    it 'ファイルが存在しない場合にMediaErrorを発生する' do
      allow(File).to receive(:exist?).with(audio_path).and_return(false)

      expect {
        described_class.normalize_audio(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /not found/)
    end

    it 'ffmpeg失敗時にMediaErrorを発生する' do
      allow(Open3).to receive(:capture3).and_return(
        ['', 'error', instance_double(Process::Status, success?: false)]
      )

      expect {
        described_class.normalize_audio(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /Failed to normalize/)
    end

    it 'ffmpegタイムアウトでMediaErrorを発生する' do
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

      expect {
        described_class.normalize_audio(audio_path)
      }.to raise_error(InterviewEngine::MediaProcessor::MediaError, /timed out/)
    end
  end
end
