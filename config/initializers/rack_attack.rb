# config/initializers/rack_attack.rb
#
# APIレート制限設定
# テスト環境ではMemoryStoreを使用、本番ではRedis推奨
#
class Rack::Attack
  # キャッシュストア設定
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### ホワイトリスト ###

  # ローカルホストは常に許可
  safelist('allow-localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  ### スロットリング（レート制限） ###

  # API全体: 1IPあたり60リクエスト/分
  throttle('api/global', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  # 面接開始: 1IPあたり10リクエスト/分（新規面接の乱用防止）
  throttle('api/interviews/start', limit: 10, period: 1.minute) do |req|
    req.ip if req.path == '/api/interviews/start' && req.post?
  end

  # トークン開始: 1IPあたり20リクエスト/分（トークン総当たり防止）
  throttle('api/interviews/start_by_token', limit: 20, period: 1.minute) do |req|
    req.ip if req.path == '/api/interviews/start_by_token' && req.post?
  end

  # 回答送信: 1IPあたり30リクエスト/分（音声/動画アップロードの制限）
  throttle('api/interviews/submit_answer', limit: 30, period: 1.minute) do |req|
    req.ip if req.path =~ %r{/api/interviews/\d+/submit_answer} && req.post?
  end

  # 面接完了: 1IPあたり10リクエスト/分
  throttle('api/interviews/complete', limit: 10, period: 1.minute) do |req|
    req.ip if req.path =~ %r{/api/interviews/\d+/complete} && req.post?
  end

  # Devise認証: ログイン試行 1IPあたり10回/分（ブルートフォース防止）
  throttle('auth/login', limit: 10, period: 1.minute) do |req|
    req.ip if req.path =~ %r{/(users|clients|admins)/sign_in} && req.post?
  end

  ### ブロックリスト ###

  # 明示的にブロックされたIPをチェック（ENV経由で設定）
  blocklist('block-bad-ips') do |req|
    blocked = ENV['BLOCKED_IPS'].to_s.split(',').map(&:strip)
    blocked.include?(req.ip) if blocked.any?
  end

  ### レスポンスカスタマイズ ###

  # スロットリング時のレスポンス（429 Too Many Requests）
  self.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data'] || {}
    now = match_data[:epoch_time] || Time.now.to_i
    retry_after = match_data[:period] ? (match_data[:period] - (now % match_data[:period])) : 60

    headers = {
      'Content-Type' => 'application/json',
      'Retry-After' => retry_after.to_s,
      'X-RateLimit-Limit' => (match_data[:limit] || 60).to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + retry_after).to_s
    }

    body = {
      success: false,
      error: 'Rate limit exceeded. Please try again later.',
      retry_after: retry_after
    }.to_json

    [429, headers, [body]]
  end

  # ブロック時のレスポンス（403 Forbidden）
  self.blocklisted_responder = lambda do |request|
    headers = { 'Content-Type' => 'application/json' }
    body = { success: false, error: 'Access denied.' }.to_json
    [403, headers, [body]]
  end
end
