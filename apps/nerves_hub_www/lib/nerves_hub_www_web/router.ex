defmodule NervesHubWWWWeb.Router do
  use NervesHubWWWWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {NervesHubWWWWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(NervesHubWWWWeb.Plugs.SetLocale)
  end

  pipeline :logged_in do
    plug(NervesHubWWWWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :org do
    plug(NervesHubWWWWeb.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubWWWWeb.Plugs.Product)
  end

  pipeline :device do
    plug(NervesHubWWWWeb.Plugs.Device)
  end

  pipeline :deployment do
    plug(NervesHubWWWWeb.Plugs.Deployment)
  end

  pipeline :firmware do
    plug(NervesHubWWWWeb.Plugs.Firmware)
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

    scope "/settings/:org_name" do
      pipe_through(:org)

      get("/", OrgController, :edit)
      put("/", OrgController, :update)

      get("/invite", OrgController, :invite)
      post("/invite", OrgController, :send_invite)
      get("/certificates", OrgCertificateController, :index)
      post("/certificates", OrgCertificateController, :create)
      get("/certificates/new", OrgCertificateController, :new)
      delete("/certificates/:serial", OrgCertificateController, :delete)
      get("/certificates/:serial/edit", OrgCertificateController, :edit)
      put("/certificates/:serial", OrgCertificateController, :update)
      get("/users", OrgUserController, :index)
      get("/users/:user_id", OrgUserController, :edit)
      put("/users/:user_id", OrgUserController, :update)
      delete("/users/:user_id", OrgUserController, :delete)

      resources("/keys", OrgKeyController)
    end

    scope "/account/:user_name" do
      get("/", AccountController, :edit)
      put("/", AccountController, :update)

      scope "/certificates" do
        get("/", AccountCertificateController, :index)
        get("/new", AccountCertificateController, :new)
        get("/:id", AccountCertificateController, :show)
        delete("/:id", AccountCertificateController, :delete)
        post("/create", AccountCertificateController, :create)
        get("/:id/download", AccountCertificateController, :download)
      end

      get("/organizations", OrgController, :index)
    end

    get("/org/new", OrgController, :new)
    post("/org", OrgController, :create)

    scope "/org/:org_name" do
      pipe_through(:org)

      get("/", ProductController, :index)
      get("/new", ProductController, :new)
      post("/", ProductController, :create)

      scope "/:product_name" do
        pipe_through(:product)

        get("/", ProductController, :show)
        get("/edit", ProductController, :edit)
        put("/", ProductController, :update)
        delete("/", ProductController, :delete)

        scope "/devices" do
          get("/", DeviceController, :index)
          post("/", DeviceController, :create)
          get("/new", DeviceController, :new)
          get("/export", ProductController, :devices_export)

          scope "/:device_identifier" do
            pipe_through(:device)

            get("/", DeviceController, :show)
            get("/console", DeviceController, :console)
            get("/edit", DeviceController, :edit)
            patch("/", DeviceController, :update)
            put("/", DeviceController, :update)
            delete("/", DeviceController, :delete)
          end
        end

        scope "/firmware" do
          get("/", FirmwareController, :index)
          get("/upload", FirmwareController, :upload)
          post("/upload", FirmwareController, :do_upload)

          scope "/:firmware_uuid" do
            pipe_through(:firmware)

            get("/", FirmwareController, :show)
            get("/download", FirmwareController, :download)
            delete("/", FirmwareController, :delete)
          end
        end

        scope "/deployments" do
          get("/", DeploymentController, :index)
          post("/", DeploymentController, :create)
          get("/new", DeploymentController, :new)

          scope "/:deployment_name" do
            pipe_through(:deployment)

            get("/show", DeploymentController, :show)
            get("/edit", DeploymentController, :edit)
            patch("/", DeploymentController, :update)
            put("/", DeploymentController, :update)
            delete("/", DeploymentController, :delete)
          end
        end
      end
    end
  end

  if Mix.env() in [:dev] do
    scope "/dev" do
      pipe_through([:browser])
      forward("/mailbox", Bamboo.SentEmailViewerPlug, base_path: "/dev/mailbox")
    end
  end
end
