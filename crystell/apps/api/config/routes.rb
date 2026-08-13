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
      post "/mfa/recovery-codes/regenerate", to: "mfa#regenerate_recovery_codes"
      delete "/mfa", to: "mfa#destroy"
      post "/password-reset/request", to: "password_resets#create"
      post "/password-reset/confirm", to: "password_resets#update"
      post "/email-verification/request", to: "email_verifications#create"
      post "/email-verification/confirm", to: "email_verifications#update"
    end

    namespace :security do
      resources :sessions, only: %i[index destroy] do
        collection do
          delete :others, action: :revoke_others
        end
      end
    end

    namespace :billing do
      resources :plans, only: :index
      resource :subscription, only: %i[show create destroy] do
        post :resume
      end
      resources :invoices, only: :index
      resources :entitlements, only: :index
    end

    resources :tenant_invitations, only: %i[index create destroy]
    post "/invitations/accept", to: "invitations#accept"
    post "/tenant/ownership-transfer", to: "tenant_ownership#transfer"

    get "/me", to: "me#show"
    resources :stores, only: :index
  end
end
