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

    get "/me", to: "me#show"
    resources :stores, only: :index
  end
end
