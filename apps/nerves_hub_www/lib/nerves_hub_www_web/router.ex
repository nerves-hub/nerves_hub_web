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

  pipeline :org_level do
    plug(NervesHubWWWWeb.Plugs.FetchOrg)
  end

  pipeline :product_level do
    plug(NervesHubWWWWeb.Plugs.FetchProduct)
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
  end

  scope "/", NervesHubWWWWeb do
    pipe_through([:browser, :logged_in])

    put("/set_org", SessionController, :set_org)

    resources("/dashboard", DashboardController, only: [:index])

    get("/org/invite", OrgController, :invite)
    post("/org/invite", OrgController, :send_invite)
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

    resources("/devices", DeviceController)

    resources "/products", ProductController, except: [:edit, :update] do
      pipe_through(:product_level)

      get("/firmware", FirmwareController, :index)
      get("/firmware/upload", FirmwareController, :upload)
      post("/firmware/upload", FirmwareController, :do_upload)
      get("/firmware/download/:id", FirmwareController, :download)
      delete("/firmware/delete/:id", FirmwareController, :delete)

      resources("/deployments", DeploymentController)
    end
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
