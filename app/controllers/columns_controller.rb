class ColumnsController < ApplicationController
  before_action :authenticate_admin!, except: [:index, :show]
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve]
  before_action :set_breadcrumbs

  def index
    # statusがdraft以外、かつ bodyが空でないものだけを取得
    columns = Column.where.not(status: "draft").where.not(body: [nil, ""])

    columns = columns.where(status: params[:status]) if params[:status].present?

    # 親/子のフィルタリングボタン用
    if params[:article_type].present?
      columns = columns.where(article_type: params[:article_type])
    end

    # ジャンル検索
    if params[:genre].present?
      allowed_genres = Column::GENRE_MAPPING[params[:genre]] || [params[:genre]]
      columns = columns.where(genre: allowed_genres)
    end

    @columns = columns.order(updated_at: :desc)

    column_ids = @columns.map(&:id)

    # bodyが空でない子記事のみをカウント
    @child_counts = if column_ids.any?
      Column.where(parent_id: column_ids)
            .where.not(body: [nil, ""])
            .group(:parent_id)
            .count
    else
      {}
    end
  end

  def show
    # set_column で既に @column は取得済みのため、find_by は不要です。

    # --- SEO対策: 正規URLへのリダイレクト ---
    is_valid_genre = @column.genre.present? && @column.genre.match?(/cargo|security|cleaning|app|construction/)

    correct_path = if is_valid_genre
                     nested_column_path(genre: @column.genre, id: @column.code)
                   else
                     column_path(@column)
                   end

    if request.path != correct_path
      return redirect_to correct_path, status: :moved_permanently
    end

    # --- 親記事（pillar）の場合は子記事を取得 ---
    if @column.article_type == "pillar"
      # statusがdraft以外、かつ bodyが空でないものに絞り込み
      @children = @column.children
                         .where.not(status: "draft")
                         .where.not(body: [nil, ""])
                         .order(updated_at: :desc)
    else
      @children = []
    end

    # --- Markdown 処理 ---
    markdown_body = @column.body.presence || "## 記事はまだ生成されていません。"
    raw_html_body = Kramdown::Document.new(markdown_body).to_html

    sanitized_html_body = raw_html_body
      .gsub(/<span[^>]*>|<\/span>/, '')
      .gsub(/ style=\"[^\"]*\"/, '')

    @headings = []
    @column_body_with_ids = sanitized_html_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do
      tag  = Regexp.last_match(1)
      text = Regexp.last_match(2)
      idx = @headings.size
      @headings << { tag: tag, text: text, id: "heading-#{idx}", level: tag[1].to_i }
      "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
    end
  end

  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    if @column.save
      redirect_to columns_path, notice: "作成しました"
    else
      render 'new'
    end
  end

  def edit
    add_breadcrumb "記事編集", edit_column_path(@column)
  end

  def update
    if @column.update(column_params)
      redirect_to columns_path, notice: "更新しました"
    else
      render 'edit'
    end
  end

  def destroy
    @column.destroy
    redirect_to columns_path, notice: "削除しました"
  end

  def generate_gemini
    batch = params[:batch] || 20
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)
    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end

  def draft
    # statusがdraftのもの、または本文が空（生成未完了・失敗）のものをまとめて取得
    @columns = Column.where(status: "draft").or(Column.where(body: [nil, ""])).order(created_at: :desc)
  end

  # ----- 個別承認 -----
  def approve
    unless @column.approved?
      @column.update!(status: "approved")
      # 親子判定で本文生成ジョブを呼ぶ
      GenerateColumnBodyJob.perform_later(@column.id)
    end
    redirect_to columns_path, notice: "承認しました。本文生成を開始します。"
  end

  # ----- 一括承認・削除 -----
  def bulk_update_drafts
    column_ids = params[:column_ids]
    unless column_ids.present?
      redirect_to draft_columns_path, alert: "操作対象のドラフトが選択されていません。"
      return
    end
    case params[:action_type]
    when "approve_bulk"
      columns = Column.where(id: column_ids)
      columns.each do |column|
        unless column.approved?
          column.update!(status: "approved")
          GenerateColumnBodyJob.perform_later(column.id)
        end
      end
      redirect_to columns_path, notice: "#{columns.count}件の生成ジョブをキューに入れました。順次生成されます。"
    when "delete_bulk"
      count = Column.where(id: column_ids).destroy_all
      redirect_to draft_columns_path, notice: "#{count}件のドラフトを削除しました。"
    else
      redirect_to draft_columns_path, alert: "無効な操作が選択されました。"
    end
  end

  def generate_pillar
    title    = params[:title]
    genre    = params[:genre]
    category = params[:choice]

    if title.present?
      column = GptPillarGenerator.generate_full_article(title, genre, category)

      if column
        redirect_to draft_columns_path, notice: "親記事「#{title}」のドラフトを作成しました。一覧から本文生成を実行してください。"
      else
        redirect_to new_column_path, alert: "生成に失敗しました。"
      end
    else
      redirect_to new_column_path, alert: "タイトルを入力してください。"
    end
  end

  def generate_from_selected
    ids = params[:column_ids]

    if ids.blank?
      redirect_to draft_columns_path, alert: "親記事を選択してください"
      return
    end

    columns = Column.where(id: ids, article_type: "pillar")

    if columns.empty?
      redirect_to draft_columns_path, alert: "有効な親記事が見つかりません"
      return
    end

    # 直接実行せず、1件ずつJobに登録する
    columns.each do |column|
      GenerateColumnBodyJob.perform_later(column.id)
    end

    redirect_to draft_columns_path,
                notice: "#{columns.count}件の生成をバックグラウンドで開始しました。完了まで数分お待ちください。"
  end

  def generate_from_pillar
    @column = Column.find_by(id: params[:id]) || Column.find_by!(code: params[:id])

    unless @column.article_type == "pillar"
      redirect_to column_path(@column), alert: "親記事（pillar）以外からは子記事を生成できません。"
      return
    end

    # 直接 GeminiColumnGenerator を呼ばず、Jobに丸投げする
    GenerateChildColumnsJob.perform_later(@column.id, 25)
    redirect_to column_path(@column), notice: "子記事25件の生成をバックグラウンドで開始しました。数分後に確認してください。"
  end

  private

  def set_column
    @column = Column.friendly.find(params[:id])
  end

  def set_breadcrumbs
    add_breadcrumb 'トップ', root_path

    genre_key = @column&.genre.present? ? @column.genre : params[:genre]

    if defined?(LpDefinition)
      label = LpDefinition.label(genre_key)
      add_breadcrumb label, "/#{genre_key}" if label
    end

    add_breadcrumb @column.title if action_name == 'show' && @column
  end

  def column_params
    params.require(:column).permit(
      :title,
      :file,
      :choice,
      :keyword,
      :description,
      :genre,
      :code,
      :body,
      :status,
      :article_type,
      :parent_id,
      :cluster_limit,
      :prompt
    )
  end
end
