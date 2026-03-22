require 'rails_helper'

RSpec.describe 'Admin::InterviewResults', type: :request do
  let(:admin) { create(:admin) }
  let(:client_record) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client_record) }
  let(:user) { create(:user) }
  let(:interview) { create(:interview, :in_progress, user: user, situation: situation) }
  let!(:result) do
    interview.complete!
    create(:interview_result, interview: interview, final_status: :passed,
           results_data: { 'average_score' => 85, 'total_questions' => 3 })
  end

  describe 'GET /admin/interview_results' do
    context '管理者として認証済み' do
      before { sign_in admin }

      it '全面接結果一覧を表示する' do
        get '/admin/interview_results'
        expect(response).to have_http_status(:ok)
      end

      it '複数の結果を表示できる' do
        user2 = create(:user)
        interview2 = create(:interview, :in_progress, user: user2, situation: situation)
        interview2.complete!
        create(:interview_result, interview: interview2, final_status: :failed)

        get '/admin/interview_results'
        expect(response).to have_http_status(:ok)
      end
    end

    context '未認証' do
      it 'ログインページにリダイレクトする' do
        get '/admin/interview_results'
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context 'Client認証' do
      before { sign_in client_record }

      it '管理者ページにアクセスできない' do
        get '/admin/interview_results'
        # Devise認証フィルターにより、admin未認証としてリダイレクト
        expect(response.status).to be_in([302, 401, 403])
      end
    end

    context 'User認証' do
      before { sign_in user }

      it '管理者ページにアクセスできない' do
        get '/admin/interview_results'
        expect(response.status).to be_in([302, 401, 403])
      end
    end
  end

  describe 'GET /admin/interview_results/:id' do
    context '管理者として認証済み' do
      before { sign_in admin }

      it '面接結果詳細を表示する' do
        get "/admin/interview_results/#{result.id}"
        expect(response).to have_http_status(:ok)
      end

      it '存在しないIDで404を返す' do
        expect {
          get '/admin/interview_results/99999'
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context '未認証' do
      it 'ログインページにリダイレクトする' do
        get "/admin/interview_results/#{result.id}"
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end
end
