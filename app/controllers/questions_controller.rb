# app/controllers/questions_controller.rb
class QuestionsController < ApplicationController
  before_action :authenticate_client!
  before_action :set_situation
  before_action :set_question, only: [:edit, :update, :destroy]

  def index
    @questions = @situation.questions.order(:order)
  end

  def new
    @question = @situation.questions.new
  end

  def create
    @question = @situation.questions.new(question_params)
    if @question.save
      redirect_to situation_questions_path(@situation), notice: '質問を作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to situation_questions_path(@situation), notice: '質問を更新しました。'
    else
      render :edit
    end
  end

  def destroy
    @question.destroy
    redirect_to situation_questions_path(@situation), notice: '質問を削除しました。'
  end

  private

  def set_situation
    @situation = current_client.situations.find(params[:situation_id])
  end

  def set_question
    @question = @situation.questions.find(params[:id])
  end

  def question_params
    raw = params.require(:question).permit(
      :question_text, :question_type, :order,
      :required, :category, :correct, :branching_default_action,
      choices: [],
      branching_conditions: {}
    )

    build_options(raw)
    build_branching_rules(raw)

    raw.except(:choices, :correct, :branching_conditions, :branching_default_action)
  end

  def build_options(permitted)
    choices = (permitted[:choices] || []).reject(&:blank?)
    correct = permitted[:correct].presence

    if choices.present?
      opt = { 'choices' => choices }
      opt['correct'] = correct if correct
      permitted[:options] = opt
    else
      permitted[:options] = nil
    end
  end

  def build_branching_rules(permitted)
    raw_conditions = permitted[:branching_conditions]
    default_action = permitted[:branching_default_action] || 'skip'

    conditions = []
    if raw_conditions.is_a?(ActionController::Parameters) || raw_conditions.is_a?(Hash)
      raw_conditions.each_value do |cond|
        next if cond['source_question_order'].blank? && cond['type'].blank?
        conditions << {
          'source_question_order' => cond['source_question_order'].to_i,
          'type' => cond['type'],
          'value' => cond['value'],
          'action' => cond['action']
        }
      end
    end

    if conditions.present?
      permitted[:branching_rules] = { 'conditions' => conditions, 'default_action' => default_action }
    else
      permitted[:branching_rules] = nil
    end
  end
end
