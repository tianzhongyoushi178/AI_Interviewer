require 'rails_helper'

RSpec.describe 'Client::InterviewResults', type: :request do
  let(:client_record) { create(:client) }
  let(:other_client) { create(:client) }
  let(:situation) { create(:situation, :with_questions, client: client_record) }
  let(:other_situation) { create(:situation, :with_questions, client: other_client) }
  let(:user) { create(:user) }
  let(:interview) { create(:interview, :in_progress, user: user, situation: situation) }
  let!(:result) do
    interview.complete!
    create(:interview_result, interview: interview, final_status: :passed,
           results_data: { 'average_score' => 85, 'total_questions' => 3 })
  end

  describe 'GET /client/interview_results' do
    context 'Client認証済み' do
      before { sign_in client_record }

      it '自分のClient配下の面接結果一覧を表示する' do
        get '/client/interview_results'
        expect(response).to have_http_status(:ok)
      end
    end

    context '未認証' do
      it 'ログインページにリダイレクトする' do
        get '/client/interview_results'
        expect(response).to redirect_to(new_client_session_path)
      end
    end

    context 'User認証' do
      before { sign_in user }

      it 'Clientページにアクセスできない' do
        get '/client/interview_results'
        expect(response.status).to be_in([302, 401, 403])
      end
    end
  end

  describe 'GET /client/interview_results/:id' do
    context 'Client認証済み（自分の結果）' do
      before { sign_in client_record }

      it '自分のClient配下の結果詳細を表示する' do
        get "/client/interview_results/#{result.id}"
        expect(response).to have_http_status(:ok)
      end
    end

    context 'Client認証済み（他Clientの結果）' do
      before { sign_in other_client }

      it '他Clientの結果にアクセスできない' do
        expect {
          get "/client/interview_results/#{result.id}"
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context '未認証' do
      it 'ログインページにリダイレクトする' do
        get "/client/interview_results/#{result.id}"
        expect(response).to redirect_to(new_client_session_path)
      end
    end
  end
end
