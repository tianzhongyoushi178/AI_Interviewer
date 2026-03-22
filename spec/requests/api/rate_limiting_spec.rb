require 'rails_helper'

RSpec.describe 'API Rate Limiting', type: :request do
  let(:client_record) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client_record) }
  let!(:user) { create(:user) }

  before do
    # テストモード有効化
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('AI_INTERVIEW_TEST_MODE').and_return('true')
    allow(ENV).to receive(:[]).with('BLOCKED_IPS').and_return(nil)

    # Rack::Attackキャッシュをリセット
    Rack::Attack.cache.store.clear
    # localhostセーフリストを無効化（テスト用）
    Rack::Attack.safelists.delete('allow-localhost')
  end

  after do
    # セーフリストを復元
    Rack::Attack.safelist('allow-localhost') do |req|
      req.ip == '127.0.0.1' || req.ip == '::1'
    end
  end

  describe 'API全体のレート制限' do
    it '制限内のリクエストは正常に処理される' do
      post '/api/interviews/start', params: { situation_id: situation.id }, as: :json

      expect(response.status).not_to eq(429)
    end

    it '制限超過で429を返す' do
      61.times do
        get "/api/interviews/99999/status"
      end

      expect(response.status).to eq(429)
      body = JSON.parse(response.body)
      expect(body['error']).to include('Rate limit')
    end
  end

  describe '面接開始のレート制限' do
    it '10回以内は正常に処理される' do
      10.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      # 最後のリクエストは429ではない（10回まで許可）
      expect(response.status).not_to eq(429)
    end

    it '10回超過で429を返す' do
      11.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      expect(response.status).to eq(429)
    end
  end

  describe 'トークン開始のレート制限' do
    it '20回超過で429を返す' do
      21.times do
        post '/api/interviews/start_by_token', params: { access_token: 'test' }, as: :json
      end

      expect(response.status).to eq(429)
    end
  end

  describe '429レスポンスのフォーマット' do
    it 'JSON形式でエラー情報を返す' do
      11.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      expect(response.status).to eq(429)
      expect(response.content_type).to include('application/json')

      body = JSON.parse(response.body)
      expect(body['success']).to be false
      expect(body['error']).to be_present
      expect(body['retry_after']).to be_a(Integer)
    end

    it 'Retry-Afterヘッダーを含む' do
      11.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      expect(response.headers['Retry-After']).to be_present
    end

    it 'X-RateLimitヘッダーを含む' do
      11.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      expect(response.headers['X-RateLimit-Limit']).to be_present
      expect(response.headers['X-RateLimit-Remaining']).to eq('0')
    end
  end

  describe 'IPブロックリスト' do
    it 'ブロックされたIPからのリクエストを拒否する' do
      allow(ENV).to receive(:[]).with('BLOCKED_IPS').and_return('127.0.0.1')

      post '/api/interviews/start', params: { situation_id: situation.id }, as: :json

      expect(response.status).to eq(403)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Access denied.')
    end
  end

  describe 'localhostセーフリスト' do
    it 'セーフリスト有効時はレート制限を受けない' do
      # セーフリストを復元
      Rack::Attack.safelist('allow-localhost') do |req|
        req.ip == '127.0.0.1' || req.ip == '::1'
      end

      15.times do
        post '/api/interviews/start', params: { situation_id: situation.id }, as: :json
      end

      # localhostはセーフリストにより制限を受けない
      expect(response.status).not_to eq(429)
    end
  end
end
