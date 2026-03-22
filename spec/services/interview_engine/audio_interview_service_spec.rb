require 'rails_helper'

RSpec.describe InterviewEngine::AudioInterviewService do
  let(:client) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client, language: 'ja') }
  let(:interview) { create(:interview, :in_progress, user: create(:user), situation: situation) }
  let(:service) { described_class.new(interview) }

  describe '#process_answer_media' do
    context 'テキスト回答' do
      it 'テキスト回答をそのまま返す' do
        result = service.process_answer_media(text_answer: 'テスト回答です')

        expect(result[:transcript]).to eq('テスト回答です')
        expect(result[:audio_path]).to be_nil
        expect(result[:extracted_audio_path]).to be_nil
      end
    end

    context '音声ファイル' do
      let(:audio_file) do
        tmpfile = Tempfile.new(['test', '.wav'])
        tmpfile.write('fake_audio_data')
        tmpfile.rewind
        tmpfile
      end

      after { audio_file.close; audio_file.unlink }

      it '音声ファイルからトランスクリプトを返す' do
        allow(InterviewEngine::MediaProcessor).to receive(:validate_audio_duration!)
        stt_mock = instance_double(InterviewEngine::STTClient)
        allow(InterviewEngine::STTClient).to receive(:new).and_return(stt_mock)
        allow(stt_mock).to receive(:transcribe).and_return('音声から変換されたテキスト')

        result = service.process_answer_media(audio_file: audio_file)

        expect(result[:transcript]).to eq('音声から変換されたテキスト')
        expect(result[:audio_path]).to eq(audio_file.path)
        expect(result[:extracted_audio_path]).to be_nil
      end

      it '空のトランスクリプトでAudioErrorを発生する' do
        allow(InterviewEngine::MediaProcessor).to receive(:validate_audio_duration!)
        stt_mock = instance_double(InterviewEngine::STTClient)
        allow(InterviewEngine::STTClient).to receive(:new).and_return(stt_mock)
        allow(stt_mock).to receive(:transcribe).and_return(nil)

        expect {
          service.process_answer_media(audio_file: audio_file)
        }.to raise_error(InterviewEngine::AudioInterviewService::AudioError, /Failed to transcribe/)
      end
    end

    context '動画ファイル' do
      let(:video_file) do
        tmpfile = Tempfile.new(['test', '.mp4'])
        tmpfile.write('fake_video_data')
        tmpfile.rewind
        tmpfile
      end
      let(:extracted_audio_path) { '/tmp/extracted_audio.wav' }

      after { video_file.close; video_file.unlink }

      it '動画から音声を抽出してトランスクリプトを返す' do
        allow(InterviewEngine::MediaProcessor).to receive(:extract_audio_from_video)
          .and_return(extracted_audio_path)
        allow(InterviewEngine::MediaProcessor).to receive(:validate_audio_duration!)
        stt_mock = instance_double(InterviewEngine::STTClient)
        allow(InterviewEngine::STTClient).to receive(:new).and_return(stt_mock)
        allow(stt_mock).to receive(:transcribe).and_return('動画からのテキスト')

        result = service.process_answer_media(video_file: video_file)

        expect(result[:transcript]).to eq('動画からのテキスト')
        expect(result[:extracted_audio_path]).to eq(extracted_audio_path)
      end
    end

    context '入力なし' do
      it 'AudioErrorを発生する' do
        expect {
          service.process_answer_media
        }.to raise_error(InterviewEngine::AudioInterviewService::AudioError, /No answer input/)
      end
    end
  end

  describe '#prepare_question' do
    it 'QuestionSelectorに委譲して質問データを返す' do
      question = situation.questions.first
      selector_mock = instance_double(InterviewEngine::QuestionSelector)
      allow(InterviewEngine::QuestionSelector).to receive(:new).and_return(selector_mock)
      allow(selector_mock).to receive(:prepare_question_audio).and_return({
        question_id: question.id,
        question_text: question.question_text,
        audio_url: nil
      })

      result = service.prepare_question(question)

      expect(result[:question_id]).to eq(question.id)
      expect(selector_mock).to have_received(:prepare_question_audio)
        .with(question, language: 'ja')
    end
  end

  describe '#cleanup_temp_files' do
    it '存在するファイルを削除する' do
      tmpfile = Tempfile.new('cleanup_test')
      path = tmpfile.path
      tmpfile.close

      expect(File.exist?(path)).to be true
      service.cleanup_temp_files(path)
      expect(File.exist?(path)).to be false
    end

    it 'nilパスを安全にスキップする' do
      expect {
        service.cleanup_temp_files(nil, nil)
      }.not_to raise_error
    end

    it '存在しないファイルを安全にスキップする' do
      expect {
        service.cleanup_temp_files('/nonexistent/path/file.wav')
      }.not_to raise_error
    end
  end

  describe '.pregenerate_question_audio' do
    it 'TTSClientを使って音声を生成する' do
      tts_mock = instance_double(InterviewEngine::TTSClient)
      allow(InterviewEngine::TTSClient).to receive(:new).and_return(tts_mock)
      allow(tts_mock).to receive(:speak).and_return(nil)

      # 既存のQuestionAudioがない場合、speakが呼ばれる
      expect {
        described_class.pregenerate_question_audio(situation, language: 'ja')
      }.not_to raise_error

      expect(tts_mock).to have_received(:speak).at_least(:once)
    end

    it 'TTS失敗時もエラーを発生しない' do
      tts_mock = instance_double(InterviewEngine::TTSClient)
      allow(InterviewEngine::TTSClient).to receive(:new).and_return(tts_mock)
      allow(tts_mock).to receive(:speak).and_raise(StandardError, 'TTS Error')

      expect {
        described_class.pregenerate_question_audio(situation, language: 'ja')
      }.not_to raise_error
    end
  end
end
