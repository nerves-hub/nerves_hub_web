defmodule NervesHubWWWWeb.Router do
  use NervesHubWWWWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(Phoenix.LiveView.Flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :logged_in do
    plug(NervesHubWWWWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :org_level do
    plug(NervesHubWWWWeb.Plugs.FetchOrg)
  end

  pipeline :org_read do
    plug(NervesHubWebCore.RoleValidateHelpers, org: :read)
  end

  pipeline :org_write do
    plug(NervesHubWebCore.RoleValidateHelpers, org: :write)
  end

  pipeline :product_level do
    plug(NervesHubWWWWeb.Plugs.FetchProduct)
  end

  pipeline :product_read do
    plug(NervesHubWebCore.RoleValidateHelpers, product: :read)
  end

  scope "/", NervesHubWWWWeb do
    # Use the default browser stack
    pipe_through(:browser)

    get("/", HomeController, :index)

    get("/login", SessionController, :new)
    post("/login", SessionController, :create)
    get("/logout", SessionController, :delete)

    get("/register", AccountController, :new)
    post("/register", AccountController, :create)

    get("/password-reset", PasswordResetController, :new)
    post("/password-reset", PasswordResetController, :create)
    get("/password-reset/:token", PasswordResetController, :new_password_form)
    put("/password-reset/:token", PasswordResetController, :reset)

    get("/invite/:token", AccountController, :invite)
    post("/invite/:token", AccountController, :accept_invite)

    scope "/policy" do
      get("/tos", PolicyController, :tos)
      get("/privacy", PolicyController, :privacy)
      get("/coc", PolicyController, :coc)
    end

    get("/sponsors", SponsorController, :index)

    get("/nerves_key", NervesKeyController, :index)
  end

  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in])

    put("/set_org", SessionController, :set_org)

    resources("/dashboard", DashboardController, only: [:index])

    get("/org/invite", OrgController, :invite)
    post("/org/invite", OrgController, :send_invite)
    get("/org/certificates", OrgCertificateController, :index)
    get("/org/users", OrgUserController, :index)
    resources("/org", OrgController)

    resources("/org_keys", OrgKeyController)

    get("/settings", AccountController, :edit)
    put("/settings", AccountController, :update)

    get("/account/certificates", AccountCertificateController, :index)
    get("/account/certificates/new", AccountCertificateController, :new)
    get("/account/certificates/:id", AccountCertificateController, :show)
    delete("/account/certificates/:id", AccountCertificateController, :delete)
    post("/account/certificates/create", AccountCertificateController, :create)
    get("/account/certificates/:id/download", AccountCertificateController, :download)

    resources("/devices", DeviceController, only: [:index, :create, :delete, :new])

    resources "/products", ProductController, except: [:edit, :update] do
      pipe_through(:product_level)

      get("/firmware", FirmwareController, :index)
      get("/firmware/upload", FirmwareController, :upload)
      post("/firmware/upload", FirmwareController, :do_upload)
      get("/firmware/download/:id", FirmwareController, :download)
      delete("/firmware/delete/:id", FirmwareController, :delete)

      resources("/deployments", DeploymentController, except: [:show])
    end
  end

  # LiveView routing could probably use more research and implementation
  # to integrate better with existing routing patterns. But for now,
  # let's be explicit here and pipe through role checks before
  # attempting to mount the LiveView session.
  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in, :org_write])

    live("/devices/:id/edit", DeviceLive.Edit,
      as: :device,
      session: [:auth_user_id, :current_org_id, :path_params]
    )
  end

  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in, :org_read])

    live("/devices/:id", DeviceLive.Show,
      as: :device,
      session: [:auth_user_id, :current_org_id, :path_params]
    )

    live("/devices/:id/console", DeviceLive.Console,
      as: :device,
      session: [:auth_user_id, :current_org_id, :path_params]
    )
  end

  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in, :product_level, :product_read])

    live("/products/:product_id/deployments/:id", DeploymentLive.Show,
      as: :product_deployment,
      session: [:auth_user_id, :path_params]
    )
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
