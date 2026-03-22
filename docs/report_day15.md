# AI面接インタビューシステム — Day 15 報告書

**プロジェクト:** AI面接インタビューシステム
**フェーズ:** Phase 4（テストカバレッジ拡充）— Service層テスト完了 + N+1最適化
**対象日:** Day 15
**作成日:** 2026-03-20
**フレームワーク:** Ruby on Rails 6.1.7 / Ruby 3.1.6

---

## 目次

### Day 15: テスト100%完了・Bullet導入・バグ修正
1. 概要
2. Bullet gem導入（N+1クエリ検出）
3. MediaProcessor テスト（19テスト）
4. AudioInterviewService テスト（11テスト）
5. EvaluateInterviewResponseJob テスト（8テスト）
6. バグ修正（2件）
7. テスト結果サマリー
8. 変更ファイル一覧

---

# Day 15 — テスト100%完了・Bullet導入・バグ修正

## 1. 概要

Phase 4の2日目として、**残りのService層テスト3件**（MediaProcessor, AudioInterviewService, EvaluateInterviewResponseJob）を追加し、Service層テストカバレッジを**75%→100%**に到達させた。併せて**Bullet gem**を導入しN+1クエリ検出を自動化。コード上のバグ2件（`private_class_method`配置ミス、未定義定数`MAX_FILE_SIZE`参照）も修正した。テスト総数は254→292（+38テスト）となり、全件パスを確認した。

---

## 2. Bullet gem導入（N+1クエリ検出）

### 導入内容

| 項目 | 内容 |
|------|------|
| Gem | `bullet 8.1.0` |
| 設定場所 | `config/environments/development.rb`, `config/environments/test.rb` |
| development | `enable`, `rails_logger`, `console`, `add_footer` |
| test | `enable`, `bullet_logger`, `raise: false` |

### N+1検出結果

全292テスト実行後、`log/bullet.log` は空（0バイト）。
**現時点でN+1クエリは検出されなかった。** 既存コードが適切にクエリを構成していることが確認された。

### 今後の効果

- development環境でN+1発生時にコンソール/ページフッターに警告表示
- テスト環境でログ出力（将来的に`raise: true`で例外化も可能）

---

## 3. MediaProcessor テスト（19テスト）

**ファイル:** `spec/services/interview_engine/media_processor_spec.rb`

| メソッド | テスト数 | 内容 |
|---------|---------|------|
| `.extract_audio_from_video` | 8 | 正常抽出、ファイル不存在、空ファイル、サイズ超過、ffmpeg未インストール、ffmpeg失敗、タイムアウト、空音声出力 |
| `.audio_duration` | 3 | 正常取得、ファイル不存在、ffprobe失敗 |
| `.validate_audio_duration!` | 4 | 正常、短すぎる、長すぎる、ffprobe不可時スキップ |
| `.normalize_audio` | 4 | 正常正規化、ファイル不存在、ffmpeg失敗、タイムアウト |

### モック方式

- `Open3.capture3` をスタブ化してffmpeg/ffprobeの出力を再現
- `File.exist?`, `File.size` を選択的にモック
- `@ffmpeg_available` キャッシュを各テスト前にリセット

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

### 設計ポイント

- `ActiveJob::Base.queue_adapter = :test` を設定してenqueueマッチャーを利用
- `retry_on StandardError` によりperform_now時は例外が抑制されることを考慮

---

## 6. バグ修正（2件）

### 6.1 MediaProcessor: `private_class_method` 配置ミス

**問題:** `private_class_method :validate_input!, :ensure_ffmpeg!, :execute_with_timeout` がメソッド定義の**前**に配置されており、テスト環境（eager_load: false）でクラスロード時にNameErrorが発生。

```
NameError: undefined method `validate_input!' for class MediaProcessor
```

**修正:** メソッド定義の**後**に移動。

| 修正前（108行目） | 修正後（最終行） |
|------------------|----------------|
| メソッド定義前に配置 | メソッド定義後に配置 |

### 6.2 AudioInterviewService: 未定義定数参照

**問題:** `validate_audio!` メソッド内で `STTClient::MAX_FILE_SIZE` を参照していたが、この定数は定義されていなかった。

```
NameError: uninitialized constant InterviewEngine::STTClient::MAX_FILE_SIZE
```

**修正:** `Rails.application.config.interview.stt_max_file_size` に変更（Day 12で設定値をENV化済み）。

---

## 7. テスト結果サマリー

### テスト数の推移

| 時点 | テスト数 | 増加 |
|------|---------|------|
| Day 13（Phase 3 完了） | 96 | — |
| Day 14（Service層テスト開始） | 254 | +158 |
| **Day 15（Service層テスト完了）** | **292** | **+38** |

### Service層カバレッジ

| Service | Day 14 | Day 15 |
|---------|--------|--------|
| SessionManager | 25 | 25 |
| ResponseEvaluator | 12 | 12 |
| QuestionSelector | 16 | 16 |
| RejectJudge | 16 | 16 |
| LLMClient | 10 | 10 |
| STTClient | 11 | 11 |
| TTSClient | 11 | 11 |
| ResponseValidator | 13 | 13 |
| PromptTemplate | 10 | 10 |
| **MediaProcessor** | **未** | **19** |
| **AudioInterviewService** | **未** | **11** |
| **EvaluateInterviewResponseJob** | **未** | **8** |
| **合計** | 124 | **162** |
| **カバレッジ** | **9/12 (75%)** | **12/12 (100%)** |

---

## 8. 変更ファイル一覧

### 新規作成ファイル

| ファイル | 内容 |
|---------|------|
| `spec/services/interview_engine/media_processor_spec.rb` | MediaProcessor テスト（19テスト） |
| `spec/services/interview_engine/audio_interview_service_spec.rb` | AudioInterviewService テスト（11テスト） |
| `spec/jobs/evaluate_interview_response_job_spec.rb` | EvaluateInterviewResponseJob テスト（8テスト） |

### 修正ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Gemfile` | `bullet` gem追加 |
| `config/environments/development.rb` | Bullet設定追加 |
| `config/environments/test.rb` | Bullet設定追加 |
| `app/services/interview_engine/media_processor.rb` | `private_class_method` をメソッド定義後に移動（バグ修正） |
| `app/services/interview_engine/audio_interview_service.rb` | `STTClient::MAX_FILE_SIZE` → `config.stt_max_file_size`（バグ修正） |

---

## セットアップ手順

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

## 次のステップ（Day 16 候補）

| 項目 | 優先度 | 概要 |
|------|--------|------|
| レート制限（Rack::Attack） | 高 | API保護強化 |
| 管理画面コントローラーテスト | 中 | situations, questionsのCRUD |
| Rails 7.0+ アップグレード | 低 | EOL対応 |
| メール通知機能 | 低 | ActionMailer統合 |

---

> **Day 15 完了:** Service層テスト100%達成（12/12）、Bullet gem導入、バグ2件修正。テスト数254→292（+38）。全292テストがパス。

---

*AI面接インタビューシステム — Day 15 報告書 | 2026-03-20 | master ブランチ*
