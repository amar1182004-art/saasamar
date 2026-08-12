Rails.application.routes.draw do
  get "/health", to: "health#show"
  get "/ready", to: "readiness#show"

  namespace :v1 do
    namespace :auth do
      resource :registration, only: :create
      resource :session, only: %i[create destroy]
      post "/mfa/setup", to: "mfa#setup"
      post "/mfa/confirm", to: "mfa#confirm"
      post "/mfa/challenge", to: "mfa#challenge"
    end

    namespace :security do
      resources :sessions, only: %i[index destroy] do
        collection do
          delete :others, action: :revoke_others
        end
      end
    end

    get "/me", to: "me#show"
    resources :stores, only: :index
  end
end
