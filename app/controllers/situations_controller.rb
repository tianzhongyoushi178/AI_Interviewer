# app/controllers/situations_controller.rb
class SituationsController < ApplicationController
  before_action :authenticate_client!, except: [:show]  # クライアント認証（閲覧は除く）
  before_action :set_situation, only: [:show, :edit, :update, :destroy]

  def index
    @situations = current_client.situations
  end

  def show
    @questions = @situation.questions.order(:order)
  end

  def new
    @situation = current_client.situations.new
  end

  def create
    @situation = current_client.situations.new(situation_params)
    if @situation.save
      redirect_to @situation, notice: '面接フォームを作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @situation.update(situation_params)
      redirect_to @situation, notice: '面接フォームを更新しました。'
    else
      render :edit
    end
  end

  def destroy
    @situation.destroy
    redirect_to situations_path, notice: '面接フォームを削除しました。'
  end

  private

  def set_situation
    if client_signed_in?
      @situation = current_client.situations.find(params[:id])
    else
      @situation = Situation.find(params[:id])
    end
  end

  def situation_params
    params.require(:situation).permit(
      :title, :description, :language, :archived,
      :passing_score, :allow_resume, :max_resume_count,
      :session_timeout_minutes, :reject_notify_method,
      :min_required_score, :max_consecutive_fails,
      :auto_reject_enabled, :reject_on_required_fail
    )
  end
end
