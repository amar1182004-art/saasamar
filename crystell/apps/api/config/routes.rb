Rails.application.routes.draw do
  get "/health", to: "health#show"
  get "/ready", to: "readiness#show"
end
