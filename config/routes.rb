Rails.application.routes.draw do
  # Liveness probe for the load balancer: 200 if the app boots.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"
      get "me", to: "auth#me"

      resources :resources do
        get :availability, on: :member
      end

      resources :reservations, only: %i[index show create] do
        patch :cancel, on: :member
      end
    end
  end

  # JSON 404 for unknown API paths instead of an HTML error page.
  match "api/*path", to: "errors#not_found", via: :all
end
