defmodule BeamwareWeb.Router do
  use BeamwareWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :logged_in do
    plug(BeamwareWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", BeamwareWeb do
    # Use the default browser stack
    pipe_through(:browser)

    get("/", SessionController, :new)
    post("/", SessionController, :create)
    get("/logout", SessionController, :delete)
    get("/register", AccountController, :new)
    post("/register", AccountController, :create)
    get("/password-reset", PasswordResetController, :new)
    post("/password-reset", PasswordResetController, :create)
    get("/password-reset/:token", PasswordResetController, :new_password_form)
    put("/password-reset/:token", PasswordResetController, :reset)
    get("/invite/:token", AccountController, :invite)
    post("/invite/:token", AccountController, :accept_invite)
  end

  scope "/", BeamwareWeb do
    pipe_through([:browser, :logged_in])

    get("/dashboard", DashboardController, :index)
    get("/tenant", TenantController, :edit)
    put("/tenant", TenantController, :update)

    get("/tenant/invite", TenantController, :invite)
    post("/tenant/invite", TenantController, :send_invite)

    get("/settings", AccountController, :edit)
    put("/settings", AccountController, :update)
  end

  if Mix.env() in [:dev] do
    scope "/dev" do
      pipe_through([:browser])
      forward("/mailbox", Plug.Swoosh.MailboxPreview, base_path: "/dev/mailbox")
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", BeamwareWeb do
  #   pipe_through :api
  # end
end
