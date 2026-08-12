Rails.application.routes.draw do
  get "/health", to: "health#show"
  get "/ready", to: "readiness#show"

  namespace :v1 do
    namespace :auth do
      resource :registration, only: :create
      resource :session, only: %i[create destroy]
    end

    get "/me", to: "me#show"
  end
end
