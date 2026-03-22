# AI面接インタビューシステム — Day 15・Day 16 統合報告書

**プロジェクト:** AI面接インタビューシステム
**フェーズ:** Phase 4（テストカバレッジ完了・本番セキュリティ強化）
**対象日:** Day 15・Day 16
**作成日:** 2026-03-20
**フレームワーク:** Ruby on Rails 6.1.7 / Ruby 3.1.6

---

## 目次

### Day 15: Service層テスト100%完了・Bullet導入・バグ修正
1. 概要
2. Bullet gem導入（N+1クエリ検出）
3. MediaProcessor テスト（19テスト）
4. AudioInterviewService テスト（11テスト）
5. EvaluateInterviewResponseJob テスト（8テスト）
6. バグ修正（2件）

### Day 16: Rack::Attackレート制限導入・Admin/Clientテスト
7. 概要
8. Rack::Attack レート制限導入
9. レート制限テスト（10テスト）
10. Admin::InterviewResults テスト（7テスト）
11. Client::InterviewResults テスト（6テスト）

### まとめ
12. テスト結果サマリー（Day 15→16 推移）
13. 変更ファイル一覧
14. セットアップ手順

---

# Day 15 — Service層テスト100%完了・Bullet導入・バグ修正

## 1. 概要

Phase 4の2日目として、**残りのService層テスト3件**（MediaProcessor, AudioInterviewService, EvaluateInterviewResponseJob）を追加し、Service層テストカバレッジを**75%→100%**に到達させた。併せて**Bullet gem**を導入しN+1クエリ検出を自動化。コード上のバグ2件も修正した。テスト総数は254→292（+38テスト）。

---

## 2. Bullet gem導入（N+1クエリ検出）

| 項目 | 内容 |
|------|------|
| Gem | `bullet 8.1.0` |
| development | `enable`, `rails_logger`, `console`, `add_footer` |
| test | `enable`, `bullet_logger`, `raise: false` |
| N+1検出結果 | **0件**（既存コードは適切にクエリを構成） |

---

## 3. MediaProcessor テスト（19テスト）

**ファイル:** `spec/services/interview_engine/media_processor_spec.rb`

| メソッド | テスト数 | 内容 |
|---------|---------|------|
| `.extract_audio_from_video` | 8 | 正常抽出、ファイル不存在、空ファイル、サイズ超過、ffmpeg未インストール、ffmpeg失敗、タイムアウト、空音声出力 |
| `.audio_duration` | 3 | 正常取得、ファイル不存在、ffprobe失敗 |
| `.validate_audio_duration!` | 4 | 正常、短すぎる、長すぎる、ffprobe不可時スキップ |
| `.normalize_audio` | 4 | 正常正規化、ファイル不存在、ffmpeg失敗、タイムアウト |

**モック方式:** `Open3.capture3`をスタブ化してffmpeg/ffprobeの出力を再現。`@ffmpeg_available`キャッシュを各テスト前にリセット。

---

## 4. AudioInterviewService テスト（11テスト）

**ファイル:** `spec/services/interview_engine/audio_interview_service_spec.rb`

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| テキスト回答 | 1 | そのまま返す |
| 音声ファイル | 2 | 正常トランスクリプト、空トランスクリプトエラー |
| 動画ファイル | 1 | 動画→音声抽出→STT→テキスト |
| 入力なし | 1 | AudioError発生 |
| `#prepare_question` | 1 | QuestionSelector委譲 |
| `#cleanup_temp_files` | 3 | 正常削除、nilスキップ、不存在スキップ |
| `.pregenerate_question_audio` | 2 | TTS呼び出し、TTS失敗時安全 |

---

## 5. EvaluateInterviewResponseJob テスト（8テスト）

**ファイル:** `spec/jobs/evaluate_interview_response_job_spec.rb`

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| `#perform` | 4 | Evaluator呼び出し、言語設定、テストモード実行、不存在ID |
| キュー設定 | 1 | defaultキュー確認 |
| enqueue | 2 | perform_later登録、キュー指定 |
| リトライ設定 | 1 | retry_on設定確認 |

---

## 6. バグ修正（2件）

### 6.1 MediaProcessor: `private_class_method` 配置ミス

**問題:** `private_class_method :validate_input!, :ensure_ffmpeg!, :execute_with_timeout` がメソッド定義の**前**に配置されており、テスト環境（eager_load: false）でNameErrorが発生。

**修正:** メソッド定義の**後**に移動。

### 6.2 AudioInterviewService: 未定義定数参照

**問題:** `validate_audio!` メソッド内で `STTClient::MAX_FILE_SIZE` を参照していたが未定義。

**修正:** `Rails.application.config.interview.stt_max_file_size` に変更（Day 12でENV化済み）。

---

# Day 16 — Rack::Attackレート制限導入・Admin/Clientテスト

## 7. 概要

本番環境のセキュリティ強化として**Rack::Attack**によるAPIレート制限を導入。併せて未テストだった**Admin/Client管理画面コントローラー**のテストを追加し、認証・認可の網羅的な検証を実現した。テスト総数は292→316（+24テスト）。

---

## 8. Rack::Attack レート制限導入

### 導入構成

| 項目 | 内容 |
|------|------|
| Gem | `rack-attack 6.8.0` |
| 設定ファイル | `config/initializers/rack_attack.rb` |
| キャッシュ | `ActiveSupport::Cache::MemoryStore`（本番ではRedis推奨） |

### レート制限ルール

| ルール | 対象 | 制限 | 目的 |
|--------|------|------|------|
| `api/global` | `/api/*` 全体 | 60 req/min/IP | API全体の保護 |
| `api/interviews/start` | `POST /start` | 10 req/min/IP | 面接乱用防止 |
| `api/interviews/start_by_token` | `POST /start_by_token` | 20 req/min/IP | トークン総当たり防止 |
| `api/interviews/submit_answer` | `POST /submit_answer` | 30 req/min/IP | アップロード制限 |
| `api/interviews/complete` | `POST /complete` | 10 req/min/IP | 完了乱用防止 |
| `auth/login` | Devise `sign_in` | 10 req/min/IP | ブルートフォース防止 |

### セキュリティ機能

- **ホワイトリスト:** localhost（127.0.0.1, ::1）は制限除外
- **ブロックリスト:** `ENV['BLOCKED_IPS']` で明示的なIP拒否（カンマ区切り）
- **429レスポンス:** JSON形式 + `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` ヘッダー
- **403レスポンス:** ブロックIPに対するJSON形式レスポンス

---

## 9. レート制限テスト（10テスト）

**ファイル:** `spec/requests/api/rate_limiting_spec.rb`

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| API全体レート制限 | 2 | 制限内OK、制限超過429 |
| 面接開始レート制限 | 2 | 10回内OK、11回目429 |
| トークン開始レート制限 | 1 | 21回目429 |
| 429レスポンスフォーマット | 3 | JSON形式、Retry-After、X-RateLimitヘッダー |
| IPブロックリスト | 1 | ブロックIP→403 |
| localhostセーフリスト | 1 | セーフリスト時制限なし |

---

## 10. Admin::InterviewResults テスト（7テスト）

**ファイル:** `spec/requests/admin/interview_results_spec.rb`

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| `GET /admin/interview_results` | 5 | Admin認証OK、複数結果表示、未認証リダイレクト、Client認証拒否、User認証拒否 |
| `GET /admin/interview_results/:id` | 2 | 詳細表示OK、存在しないID 404 |

---

## 11. Client::InterviewResults テスト（6テスト）

**ファイル:** `spec/requests/client/interview_results_spec.rb`

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| `GET /client/interview_results` | 3 | Client認証OK、未認証リダイレクト、User認証拒否 |
| `GET /client/interview_results/:id` | 3 | 自分の結果OK、他Clientの結果RecordNotFound、未認証リダイレクト |

**認可テストのポイント:** Client間のデータ分離を確認。Client AがClient Bの面接結果にアクセスすると`ActiveRecord::RecordNotFound`（`where(client_id: current_client.id)`によるフィルタリング）。

---

# まとめ

## 12. テスト結果サマリー（Day 15→16 推移）

### テスト数の推移

| 時点 | テスト数 | 増加 |
|------|---------|------|
| Day 13（Phase 3 完了） | 96 | — |
| Day 14（Service層テスト開始） | 254 | +158 |
| **Day 15（Service層テスト完了）** | **292** | **+38** |
| **Day 16（セキュリティ+管理画面）** | **316** | **+24** |

### カバレッジ状況

| 対象 | Day 14 | Day 15 | Day 16 |
|------|--------|--------|--------|
| Model層 | 5/13 (38%) | 5/13 (38%) | 5/13 (38%) |
| Service層 | 9/12 (75%) | **12/12 (100%)** | 12/12 (100%) |
| API層 | 31テスト | 31テスト | **41テスト** |
| 管理画面 | — | — | **Admin 7 + Client 6** |
| Job層 | — | **8テスト** | 8テスト |
| N+1検出 | — | **Bullet導入** | Bullet導入済 |
| レート制限 | — | — | **Rack::Attack 6ルール** |
| 全テスト | 254 | 292 | **316** |

### Service層テスト完了一覧

| Service | テスト数 | 追加Day |
|---------|---------|---------|
| SessionManager | 25 | Day 14 |
| ResponseEvaluator | 12 | Day 14 |
| QuestionSelector | 16 | Day 14 |
| RejectJudge | 16 | Day 14 |
| LLMClient | 10 | Day 14 |
| STTClient | 11 | Day 14 |
| TTSClient | 11 | Day 14 |
| ResponseValidator | 13 | Day 14 |
| PromptTemplate | 10 | Day 14 |
| MediaProcessor | 19 | Day 15 |
| AudioInterviewService | 11 | Day 15 |
| EvaluateInterviewResponseJob | 8 | Day 15 |

---

## 13. 変更ファイル一覧

### Day 15 新規作成ファイル

| ファイル | 内容 |
|---------|------|
| `spec/services/interview_engine/media_processor_spec.rb` | MediaProcessor テスト（19テスト） |
| `spec/services/interview_engine/audio_interview_service_spec.rb` | AudioInterviewService テスト（11テスト） |
| `spec/jobs/evaluate_interview_response_job_spec.rb` | EvaluateInterviewResponseJob テスト（8テスト） |

### Day 15 修正ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Gemfile` | `bullet` gem追加 |
| `config/environments/development.rb` | Bullet設定追加 |
| `config/environments/test.rb` | Bullet設定追加 |
| `app/services/interview_engine/media_processor.rb` | `private_class_method` 配置修正（バグ修正） |
| `app/services/interview_engine/audio_interview_service.rb` | `MAX_FILE_SIZE` → `config.stt_max_file_size`（バグ修正） |

### Day 16 新規作成ファイル

| ファイル | 内容 |
|---------|------|
| `config/initializers/rack_attack.rb` | Rack::Attack レート制限設定 |
| `spec/requests/api/rate_limiting_spec.rb` | レート制限テスト（10テスト） |
| `spec/requests/admin/interview_results_spec.rb` | Admin管理画面テスト（7テスト） |
| `spec/requests/client/interview_results_spec.rb` | Client管理画面テスト（6テスト） |
| `spec/factories/admins.rb` | Admin Factory |

### Day 16 修正ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Gemfile` | `rack-attack` gem追加 |

---

## 14. セットアップ手順

```bash
# 1. Gem インストール（production除外）
bundle config set --local without production
bundle install

# 2. DB作成・マイグレーション
bundle exec rails db:create
bundle exec rails db:migrate

# 3. テスト用DB
RAILS_ENV=test bundle exec rails db:create db:migrate

# 4. テスト実行
bundle exec rspec

# 5. 詳細レポート
bundle exec rspec --format documentation
```

---

> **Day 15:** Service層テスト100%達成（12/12）、Bullet gem導入、バグ2件修正。テスト254→292（+38）。
> **Day 16:** Rack::Attackレート制限導入（6ルール）、Admin/Clientテスト追加。テスト292→316（+24）。全316テストがパス。

---

*AI面接インタビューシステム — Day 15・Day 16 統合報告書 | 2026-03-20 | master ブランチ*
