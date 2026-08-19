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

  # --- Drive ----------------------------------------------------------------
  # /files is the root of the drive; /folders/:id browses one folder.
  resources :files, only: %i[index new create show update destroy] do
    member do
      post   :restore
      delete :purge
    end
  end

  resources :folders, only: %i[show create update destroy] do
    member do
      post   :restore
      delete :purge
    end
  end

  # Byte serving lives in its own controller because it uses
  # ActionController::Live. See FileTransfersController.
  get "files/:id/download", to: "file_transfers#download", as: :download_file
  get "files/:id/preview",  to: "file_transfers#preview",  as: :preview_file

  resource :trash, only: :show, controller: "trash"

  # --- Operations -----------------------------------------------------------
  # Returns 200 when the application boots correctly. Used by container health
  # checks and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
