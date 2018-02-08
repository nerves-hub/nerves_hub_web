defmodule BeamwareWeb.Router do
  use BeamwareWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :logged_in do
    plug BeamwareWeb.Plugs.EnsureLoggedIn
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BeamwareWeb do
    pipe_through :browser # Use the default browser stack

    get "/", SessionController, :new
    post "/", SessionController, :create
    get "/register", AccountController, :new
    post "/register", AccountController, :create
  end

  scope "/", BeamwareWeb do
    pipe_through [:browser, :logged_in]

    get "/dashboard", DashboardController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", BeamwareWeb do
  #   pipe_through :api
  # end
end
