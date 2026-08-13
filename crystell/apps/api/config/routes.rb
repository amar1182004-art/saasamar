Rails.application.routes.draw do
  get "/health", to: "health#show"
  get "/ready", to: "readiness#show"

  namespace :v1 do
    post "/payment-webhooks/:endpoint_id", to: "payment_webhooks#create"

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

    get "/stores/:store_id/storefront", to: "storefront#show"
    patch "/stores/:store_id/storefront", to: "storefront#update"
    put "/stores/:store_id/storefront", to: "storefront#update"
    post "/stores/:store_id/storefront/publish", to: "storefront#publish"

    get "/stores/:store_id/catalog/products", to: "catalog/products#index"
    post "/stores/:store_id/catalog/products", to: "catalog/products#create"
    get "/stores/:store_id/catalog/products/:id", to: "catalog/products#show"
    patch "/stores/:store_id/catalog/products/:id", to: "catalog/products#update"
    put "/stores/:store_id/catalog/products/:id", to: "catalog/products#update"
    delete "/stores/:store_id/catalog/products/:id", to: "catalog/products#destroy"

    post "/stores/:store_id/catalog/products/:product_id/variants", to: "catalog/variants#create"
    patch "/stores/:store_id/catalog/products/:product_id/variants/:id", to: "catalog/variants#update"
    put "/stores/:store_id/catalog/products/:product_id/variants/:id", to: "catalog/variants#update"
    delete "/stores/:store_id/catalog/products/:product_id/variants/:id", to: "catalog/variants#destroy"

    get "/stores/:store_id/catalog/products/:product_id/media", to: "catalog/media#index"
    post "/stores/:store_id/catalog/products/:product_id/media", to: "catalog/media#create"
    post "/stores/:store_id/catalog/products/:product_id/media/:id/complete", to: "catalog/media#complete"
    get "/stores/:store_id/catalog/products/:product_id/media/:id/preview", to: "catalog/media#preview"
    delete "/stores/:store_id/catalog/products/:product_id/media/:id", to: "catalog/media#destroy"

    get "/stores/:store_id/catalog/categories", to: "catalog/categories#index"
    post "/stores/:store_id/catalog/categories", to: "catalog/categories#create"
    patch "/stores/:store_id/catalog/categories/:id", to: "catalog/categories#update"
    put "/stores/:store_id/catalog/categories/:id", to: "catalog/categories#update"
    delete "/stores/:store_id/catalog/categories/:id", to: "catalog/categories#destroy"

    post "/stores/:store_id/catalog/products/:product_id/category_assignments", to: "catalog/category_assignments#create"
    delete "/stores/:store_id/catalog/products/:product_id/category_assignments/:id", to: "catalog/category_assignments#destroy"

    get "/stores/:store_id/inventory/locations", to: "inventory/locations#index"
    post "/stores/:store_id/inventory/locations", to: "inventory/locations#create"
    patch "/stores/:store_id/inventory/locations/:id", to: "inventory/locations#update"
    put "/stores/:store_id/inventory/locations/:id", to: "inventory/locations#update"
    delete "/stores/:store_id/inventory/locations/:id", to: "inventory/locations#destroy"

    get "/stores/:store_id/inventory/levels", to: "inventory/levels#index"
    post "/stores/:store_id/inventory/adjustments", to: "inventory/adjustments#create"
    post "/stores/:store_id/inventory/reservations", to: "inventory/reservations#create"
    post "/stores/:store_id/inventory/reservations/:id/release", to: "inventory/reservations#release"
    post "/stores/:store_id/inventory/reservations/:id/consume", to: "inventory/reservations#consume"
    post "/stores/:store_id/inventory/reservations/:id/expire", to: "inventory/reservations#expire"
  end
end
