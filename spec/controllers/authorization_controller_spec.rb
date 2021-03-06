require 'rails_helper'

RSpec.describe AuthorizationController, type: :controller do
  describe 'GET #authorize' do
    it 'returns bad request' do
      get 'authorize'
      expect(response).to have_http_status(:found)
    end
  end

  describe 'GET #callback' do
    it 'returns http success' do
      get :callback
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'GET #logout' do
    it 'returns http success' do
      get :logout
      expect(response).to have_http_status(:bad_request)
    end
  end
end
