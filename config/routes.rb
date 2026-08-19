Rails.application.routes.draw do
  # --- Authentication -------------------------------------------------------
  get    "sign_in",  to: "sessions#new"
  post   "sign_in",  to: "sessions#create"
  delete "sign_out", to: "sessions#destroy"

  get  "sign_up", to: "registrations#new"
  post "sign_up", to: "registrations#create"

  resources :passwords, param: :token, only: %i[new create edit update]

  # --- Account --------------------------------------------------------------
  resource :profile, only: %i[show update]

  namespace :profile do
    resource  :password, only: :update
    resources :sessions, only: %i[index destroy]
  end

  # --- Operations -----------------------------------------------------------
  # Returns 200 when the application boots correctly. Used by container health
  # checks and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
