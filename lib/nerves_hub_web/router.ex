defmodule NervesHubWeb.Router do
  use NervesHubWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :logged_in do
    plug(NervesHubWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(NervesHubWeb.Plugs.Api.AuthenticateDevice)
  end

  scope "/", NervesHubWeb do
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

  scope "/", NervesHubWeb do
    pipe_through([:browser, :logged_in])

    get("/dashboard", DashboardController, :index)
    get("/tenant", TenantController, :edit)
    put("/tenant", TenantController, :update)
    post("/tenant/key", TenantController, :create_key)

    get("/tenant/invite", TenantController, :invite)
    post("/tenant/invite", TenantController, :send_invite)

    get("/settings", AccountController, :edit)
    put("/settings", AccountController, :update)

    get("/devices", DeviceController, :index)
    get("/devices/new", DeviceController, :new)
    post("/devices/new", DeviceController, :create)
    get("/devices/:device_id", DeviceController, :edit)
    put("/devices/:device_id", DeviceController, :update)

    get("/firmware", FirmwareController, :index)
    get("/firmware/upload", FirmwareController, :upload)
    post("/firmware/upload", FirmwareController, :do_upload)
    get("/firmware/download/:id", FirmwareController, :download)

    get("/deployments", DeploymentController, :index)
    get("/deployments/new", DeploymentController, :new)
    post("/deployments/new", DeploymentController, :create)
    get("/deployments/:deployment_id", DeploymentController, :show)
    post("/deployments/:deployment_id/toggle-active", DeploymentController, :toggle_is_active)
    delete("/deployments/:deployment_id", DeploymentController, :delete)
  end

  scope "/api", NervesHubWeb.Api do
    pipe_through(:api)

    get("/firmware-update", FirmwareUpdateController, :show)
  end

  if Mix.env() in [:dev] do
    scope "/dev" do
      pipe_through([:browser])
      forward("/mailbox", Plug.Swoosh.MailboxPreview, base_path: "/dev/mailbox")
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", NervesHubWeb do
  #   pipe_through :api
  # end
end
