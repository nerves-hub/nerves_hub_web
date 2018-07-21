defmodule NervesHubWWWWeb.Router do
  use NervesHubWWWWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :logged_in do
    plug(NervesHubWWWWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :tenant_level do
    plug(NervesHubWWWWeb.Plugs.FetchTenant)
  end

  pipeline :product_level do
    plug(NervesHubWWWWeb.Plugs.FetchProduct)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(NervesHubWWWWeb.Plugs.Api.AuthenticateDevice)
  end

  scope "/", NervesHubWWWWeb do
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
    put("/invite/:token", AccountController, :accept_invite)
  end

  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in])

    resources("/dashboard", DashboardController, only: [:index])
    get("/tenant", TenantController, :edit)
    put("/tenant", TenantController, :update)
    post("/tenant/key", TenantController, :create_key)

    get("/tenant/invite", TenantController, :invite)
    post("/tenant/invite", TenantController, :send_invite)

    get("/settings", AccountController, :edit)
    put("/settings", AccountController, :update)

    resources("/devices", DeviceController, only: [:index])

    resources "/products", ProductController do
      pipe_through(:product_level)

      get("/firmware", FirmwareController, :index)
      get("/firmware/upload", FirmwareController, :upload)
      post("/firmware/upload", FirmwareController, :do_upload)
      get("/firmware/download/:id", FirmwareController, :download)

      resources("/deployments", DeploymentController)

      resources("/devices", DeviceController)
    end
  end

  scope "/api", NervesHubWWWWeb.Api do
    pipe_through(:api)

    get("/firmware-update", FirmwareUpdateController, :show)
  end

  if Mix.env() in [:dev] do
    scope "/dev" do
      pipe_through([:browser])
      forward("/mailbox", Bamboo.SentEmailViewerPlug, base_path: "/dev/mailbox")
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", NervesHubWWWWeb do
  #   pipe_through :api
  # end
end
