Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }
  devise_for :clients, controllers: {
    sessions: 'clients/sessions',
    registrations: 'clients/registrations'
  }
  # Deviseの管理者認証
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }
  
  root to: 'tops#index'

  # --- 各ジャンルLPの定義 ---
  get 'cargo', to: 'tops#cargo'
  get 'security', to: 'tops#security'
  get 'construction', to: 'tops#construction'
  get 'cleaning', to: 'tops#cleaning'
  get 'event', to: 'tops#event'
  get 'vender', to: 'tops#vender'
  get 'logistics', to: 'tops#logistics'
  get 'short', to: 'tops#short'
  get 'recruit', to: 'tops#recruit'
  get 'app', to: 'tops#app'
  get 'ads', to: 'tops#ads'
  get 'bpo', to: 'tops#bpo'
  get 'interview', to: 'tops#interview'

  # --- SEO用: ジャンル別コラム階層 (/genre/columns/:code) ---
  scope ':genre', constraints: { genre: /cargo|security|cleaning|app|construction|vender/ } do
    resources :columns, only: [:index, :show], as: :nested_columns
  end

  get 'draft/progress', to: 'draft#progress'

  resources :contracts

  # --- 【重要修正】一括処理ルーティングを resources より上に定義 ---
  # これにより /columns/generate_from_selected が ID 検索 (/:id) より先にマッチします
  post 'columns/generate_from_selected', to: 'columns#generate_from_selected', as: :generate_from_selected_columns_fix
  post 'columns/bulk_update_drafts', to: 'columns#bulk_update_drafts', as: :bulk_update_drafts_columns_fix

  # --- 管理機能・汎用リソースとしてのコラム ---
  resources :columns do
    collection do
      get :draft            # ドラフト一覧
      post :generate_gemini # Gemini生成ボタンのPOST
      post :generate_pillar # 親専用生成ボタン
      # 以下の定義は resources 内部だと優先順位が低いため、上記の外出し定義が優先されます
      post :generate_from_selected
      match 'bulk_update_drafts', via: [:post, :patch]
    end
    member do
      post :generate_from_pillar
      patch :approve
    end
  end

  # --- 面接シナリオ管理 ---
  resources :situations do
    resources :questions, except: [:show]
  end

  # --- Sidekiq Web UI ---
  require 'sidekiq/web'
  authenticate :admin do 
    mount Sidekiq::Web, at: "/sidekiq"
  end

  # --- AI Interview System API ---
  namespace :api do
    resources :interviews, only: [] do
      member do
        get :next_question
        post :submit_answer
        post :answer, action: :submit_answer
        post :complete
        get :status
        post :resume
      end
      collection do
        post :start
        post :start_by_token
      end
    end
  end

  # GETで /api/interviews/start にアクセスされた場合は面接ページへリダイレクト
  get '/api/interviews/start', to: redirect('/interview')

  namespace :admin do
    resources :interview_results, only: [:index, :show]
  end

  namespace :client do
    resources :interview_results, only: [:index, :show]
  end
end
