# AI Interview System セットアップマニュアル

## 概要

AI面接システムのローカル開発環境構築手順です。
Ruby on Rails 6.1 ベースのWebアプリケーションで、OpenAI APIを利用したAI面接を実施できます。

---

## 動作環境

| 項目 | 要件 |
|------|------|
| Ruby | 3.1.x |
| Rails | 6.1.7 |
| DB（開発） | SQLite3（設定不要） |
| DB（本番） | PostgreSQL |
| Node.js | 14以上（アセットパイプライン用） |
| OS | Windows / macOS / Linux |

---

## セットアップ手順

### 方法A: ローカルインストール（推奨）

#### 1. リポジトリのクローン

```bash
git clone https://github.com/tianzhongyoushi178/AI_Interviewer.git
cd AI_Interviewer
```

#### 2. Rubyのインストール

**Windows（winget）:**
```bash
winget install RubyInstallerTeam.RubyWithDevKit.3.1
```
インストール後、新しいターミナルを開いてパスを反映させてください。

**macOS（Homebrew）:**
```bash
brew install ruby@3.1
```

**Linux（rbenv）:**
```bash
rbenv install 3.1.6
rbenv local 3.1.6
```

インストール確認:
```bash
ruby --version
# ruby 3.1.x が表示されればOK
```

#### 3. Gemのインストール

```bash
bundle install
```

#### 4. データベースのセットアップ

```bash
bundle exec rails db:setup
```

このコマンドで以下が一括実行されます:
- データベース作成（SQLite）
- マイグレーション実行
- Seedデータ投入（テスト用アカウント・面接データ）

#### 5. 環境変数の設定

```bash
cp .env.example .env
```

`.env` を編集し、必要に応じてAPIキーを設定:

```
# 必須（AI機能を使う場合）
OPENAI_API_KEY=sk-your-openai-api-key

# テストモード（APIキーなしで動作確認したい場合）
AI_INTERVIEW_TEST_MODE=true
```

#### 6. サーバー起動

```bash
bundle exec rails server
```

http://localhost:3000 にアクセスして動作確認。

---

### 方法B: Docker

Ruby等のインストール不要で起動できます。

#### 1. リポジトリのクローン

```bash
git clone https://github.com/tianzhongyoushi178/AI_Interviewer.git
cd AI_Interviewer
```

#### 2. 環境変数の設定

```bash
cp .env.example .env
```

`.env` を編集:
```
AI_INTERVIEW_TEST_MODE=true
```

#### 3. ビルド＆起動

```bash
docker compose up --build
```

初回はイメージのビルドに数分かかります。
http://localhost:3000 にアクセスして動作確認。

停止: `Ctrl+C` または `docker compose down`

---

## テスト用アカウント

`rails db:setup` 実行後、以下のアカウントが自動作成されます（Seedデータ）:

| ロール | メールアドレス | パスワード | ログインURL |
|--------|---------------|-----------|-------------|
| クライアント（企業） | client@interview.com | password123 | /clients/sign_in |
| 受験者 | test@interview.com | password123 | /users/sign_in |

管理者アカウントは手動で作成してください:
```bash
bundle exec rails runner "Admin.create!(email: 'admin@example.com', password: 'password123')"
```

管理者ログイン: /admins/sign_in

---

## 画面構成

| URL | 内容 | ログインロール |
|-----|------|--------------|
| / | トップページ | 不要 |
| /clients/sign_in | クライアント（企業）ログイン | - |
| /users/sign_in | 受験者ログイン | - |
| /admins/sign_in | 管理者ログイン | - |
| /situations | 面接シナリオ管理 | クライアント |
| /situations/:id/questions | 質問管理 | クライアント |
| /client/interview_results | 面接結果一覧（企業側） | クライアント |
| /admin/interview_results | 面接結果一覧（管理者） | 管理者 |

---

## API エンドポイント

面接の実行はAPIで行います:

| メソッド | エンドポイント | 機能 |
|---------|--------------|------|
| POST | /api/interviews/start | 面接開始 |
| POST | /api/interviews/start_by_token | トークンで面接開始 |
| GET | /api/interviews/:id/next_question | 次の質問を取得 |
| POST | /api/interviews/:id/submit_answer | 回答を送信 |
| GET | /api/interviews/:id/status | 進捗確認 |
| POST | /api/interviews/:id/complete | 面接完了 |
| POST | /api/interviews/:id/resume | 面接再開 |

### APIテスト例

```bash
# 面接開始
curl -X POST http://localhost:3000/api/interviews/start \
  -H "Content-Type: application/json" \
  -d '{"situation_id": 1, "language": "ja"}'

# 次の質問を取得（interview_idを置き換え）
curl http://localhost:3000/api/interviews/1/next_question?language=ja

# 回答送信
curl -X POST http://localhost:3000/api/interviews/1/submit_answer \
  -H "Content-Type: application/json" \
  -d '{"question_id": 1, "text_answer": "Railsの経験は5年あります。"}'

# 面接完了
curl -X POST http://localhost:3000/api/interviews/1/complete
```

---

## 主要な環境変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| OPENAI_API_KEY | OpenAI APIキー（AI機能に必須） | - |
| AI_INTERVIEW_TEST_MODE | テストモード（APIキーなしで動作） | false |
| CLAUDE_API_KEY | Claude APIキー（代替LLM） | - |
| REDIS_URL | Redis URL（Sidekiq/本番用） | redis://localhost:6379/0 |
| RAILS_ENV | 実行環境 | development |
| PORT | サーバーポート | 3000 |

全変数の一覧は `.env.example` を参照してください。

---

## トラブルシューティング

### ポート3000が使用中

```bash
# Windows
netstat -ano | findstr :3000
taskkill /PID <PID> /F

# macOS/Linux
lsof -i :3000
kill -9 <PID>

# 別ポートで起動
bundle exec rails server -p 3001
```

### bundle install でエラー

```bash
# Bundlerバージョンを合わせる
gem install bundler -v 2.3.26
bundle install
```

### rack-attack 起動エラー（NoMethodError: cache_store=）

rack-attack 6.8.0 以降ではAPIが変更されています。
`config/initializers/rack_attack.rb` の `cache_store=` を `cache.store=` に修正してください。
（最新版では修正済み）

### マイグレーションエラー

```bash
# データベースをリセットして再構築
bundle exec rails db:reset
```

### Windows で wdm 警告が出る

以下の警告は動作に影響しません（無視可能）:
```
Please add the following to your Gemfile to avoid polling for changes:
  gem 'wdm', '>= 0.1.0' if Gem.win_platform?
```

---

## テストの実行

```bash
# RSpecテスト全体
bundle exec rspec

# 個別のテスト
bundle exec rspec spec/models/interview_spec.rb
bundle exec rspec spec/requests/api/interviews_spec.rb
```

---

## 本番デプロイ時の注意

- PostgreSQLを使用（`DATABASE_URL` を設定）
- `OPENAI_API_KEY` を必ず設定
- `RAILS_MASTER_KEY` を設定
- Redis + Sidekiq を起動（非同期評価処理用）
- `ALLOW_ADMIN_REGISTRATION=true` は初回のみ、管理者作成後は削除

詳細は `PRODUCTION_IMPLEMENTATION_GUIDE.md` を参照してください。
