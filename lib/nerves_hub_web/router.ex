defmodule NervesHubWeb.Router do
  use NervesHubWeb, :router

  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  pipeline :browser do
    plug(:accepts, ["html", "json"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {NervesHubWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(NervesHubWeb.Plugs.SetLocale)
  end

  pipeline :dynamic_layout do
    plug(:put_dynamic_root_layout)
  end

  def put_dynamic_root_layout(conn, _) do
    session = Plug.Conn.get_session(conn)

    if Application.get_env(:nerves_hub, :new_ui) && session["new_ui"] do
      put_root_layout(conn, html: {NervesHubWeb.Layouts, :root})
    else
      put_root_layout(conn, html: {NervesHubWeb.LayoutView, :root})
    end
  end

  pipeline :logged_in do
    plug(NervesHubWeb.Plugs.FetchUser)
    plug(NervesHubWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :live_logged_in do
    plug(NervesHubWeb.Plugs.EnsureAuthenticated)
  end

  pipeline :org do
    plug(NervesHubWeb.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubWeb.Plugs.Product)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_user do
    plug(NervesHubWeb.API.Plugs.User)
  end

  pipeline :api_org do
    plug(NervesHubWeb.API.Plugs.Org)
  end

  pipeline :api_product do
    plug(NervesHubWeb.API.Plugs.Product)
  end

  pipeline :api_device do
    plug(NervesHubWeb.API.Plugs.Device)
  end

  scope("/api", NervesHubWeb.API, as: :api) do
    pipe_through(:api)

    get("/health", HealthCheckController, :health_check)

    post("/users/auth", UserController, :auth)
    post("/users/login", UserController, :login)

    scope "/devices" do
      pipe_through([:api_user])

      get("/:identifier", DeviceController, :show)
      post("/:identifier/reboot", DeviceController, :reboot)
      post("/:identifier/reconnect", DeviceController, :reconnect)
      post("/:identifier/code", DeviceController, :code)
      post("/:identifier/upgrade", DeviceController, :upgrade)
      post("/:identifier/move", DeviceController, :move)
      delete("/:identifier/penalty", DeviceController, :penalty)

      get("/:identifier/scripts", ScriptController, :index)
      post("/:identifier/scripts/:id", ScriptController, :send)
    end

    scope "/" do
      pipe_through([:api_user])

      get("/users/me", UserController, :me)

      scope "/orgs" do
        scope "/:org_name" do
          pipe_through([:api_org])

          scope "/users" do
            get("/", OrgUserController, :index)
            post("/", OrgUserController, :add)
            get("/:user_id", OrgUserController, :show)
            put("/:user_id", OrgUserController, :update)
            delete("/:user_id", OrgUserController, :remove)
          end

          scope "/keys" do
            get("/", KeyController, :index)
            post("/", KeyController, :create)
            get("/:name", KeyController, :show)
            delete("/:name", KeyController, :delete)
          end

          scope "/ca_certificates" do
            get("/", CACertificateController, :index)
            post("/", CACertificateController, :create)
            get("/:serial", CACertificateController, :show)
            delete("/:serial", CACertificateController, :delete)
          end

          scope "/products" do
            get("/", ProductController, :index)
            post("/", ProductController, :create)

            scope "/:product_name" do
              pipe_through([:api_product])

              get("/", ProductController, :show)
              delete("/", ProductController, :delete)
              put("/", ProductController, :update)

              scope "/devices" do
                get("/", DeviceController, :index)
                post("/", DeviceController, :create)
                post("/auth", DeviceController, :auth)

                scope "/:identifier" do
                  pipe_through([:api_device])

                  get("/", DeviceController, :show)
                  delete("/", DeviceController, :delete)
                  put("/", DeviceController, :update)
                  post("/reboot", DeviceController, :reboot)
                  post("/reconnect", DeviceController, :reconnect)
                  post("/code", DeviceController, :code)
                  post("/upgrade", DeviceController, :upgrade)
                  delete("/penalty", DeviceController, :penalty)

                  scope "/certificates" do
                    get("/", DeviceCertificateController, :index)
                    get("/:serial", DeviceCertificateController, :show)
                    post("/", DeviceCertificateController, :create)
                    delete("/:serial", DeviceCertificateController, :delete)
                  end
                end
              end

              scope "/firmwares" do
                get("/", FirmwareController, :index)
                get("/:uuid", FirmwareController, :show)
                post("/", FirmwareController, :create)
                delete("/:uuid", FirmwareController, :delete)
              end

              scope "/deployments" do
                get("/", DeploymentController, :index)
                post("/", DeploymentController, :create)
                get("/:name", DeploymentController, :show)
                put("/:name", DeploymentController, :update)
                delete("/:name", DeploymentController, :delete)
              end
            end
          end
        end
      end
    end
  end

  scope "/", NervesHubWeb do
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
  end

  scope "/org/:org_name/:product_name", NervesHubWeb do
    pipe_through([:browser, :logged_in, :org, :product])

    get("/devices/export", ProductController, :devices_export)

    scope "/devices/:identifier" do
      get("/console", DeviceController, :console)
      get("/certificate/:serial/download", DeviceController, :download_certificate)
      get("/audit_logs/download", DeviceController, :export_audit_logs)
    end

    get("/archives/:uuid/download", DownloadController, :archive)
    get("/firmware/:uuid/download", DownloadController, :firmware)
    get("/deployments/:name/audit_logs/download", DeploymentController, :export_audit_logs)
  end

  scope "/", NervesHubWeb do
    pipe_through([:browser, :live_logged_in, :dynamic_layout])

    get("/ui/switch", UiSwitcherController, :index)

    live_session :account,
      on_mount: [
        NervesHubWeb.Mounts.AccountAuth,
        NervesHubWeb.Mounts.CurrentPath,
        {NervesHubWeb.Mounts.LayoutSelector, :no_sidebar}
      ] do
      live("/account", Live.Account, :edit)
      live("/account/delete", Live.Account, :delete)
      live("/account/tokens", Live.AccountTokens, :index)
      live("/account/tokens/new", Live.AccountTokens, :new)

      live("/orgs", Live.Orgs.Index)
      live("/orgs/new", Live.Orgs.New)
    end

    live_session :org,
      on_mount: [
        NervesHubWeb.Mounts.AccountAuth,
        NervesHubWeb.Mounts.CurrentPath,
        NervesHubWeb.Mounts.FetchOrg,
        NervesHubWeb.Mounts.FetchOrgUser,
        {NervesHubWeb.Mounts.LayoutSelector, :no_sidebar}
      ] do
      live("/org/:org_name", Live.Org.Products, :index)
      live("/org/:org_name/new", Live.Org.Products, :new)
      live("/org/:org_name/settings", Live.Org.Settings)
      live("/org/:org_name/settings/keys", Live.Org.SigningKeys, :index)
      live("/org/:org_name/settings/keys/new", Live.Org.SigningKeys, :new)
      live("/org/:org_name/settings/users", Live.Org.Users, :index)
      live("/org/:org_name/settings/users/invite", Live.Org.Users, :invite)
      live("/org/:org_name/settings/users/:user_id/edit", Live.Org.Users, :edit)
      live("/org/:org_name/settings/certificates", Live.Org.CertificateAuthorities, :index)
      live("/org/:org_name/settings/certificates/new", Live.Org.CertificateAuthorities, :new)
      live("/org/:org_name/settings/delete", Live.Org.Delete)

      live(
        "/org/:org_name/settings/certificates/:serial/edit",
        Live.Org.CertificateAuthorities,
        :edit
      )
    end

    live_session :product,
      on_mount: [
        NervesHubWeb.Mounts.AccountAuth,
        NervesHubWeb.Mounts.CurrentPath,
        NervesHubWeb.Mounts.FetchOrg,
        NervesHubWeb.Mounts.FetchOrgUser,
        NervesHubWeb.Mounts.FetchProduct,
        {NervesHubWeb.Mounts.LayoutSelector, :sidebar}
      ] do
      live("/org/:org_name/:product_name/dashboard", Live.Dashboard.Index)

      live("/org/:org_name/:product_name/devices", Live.Devices.Index)
      live("/org/:org_name/:product_name/devices/new", Live.Devices.New)
      live("/org/:org_name/:product_name/devices/:device_identifier", Live.Devices.Show, :details)

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/healthz",
        Live.Devices.Show,
        :health
      )

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/activity",
        Live.Devices.Show,
        :activity
      )

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/conzole",
        Live.Devices.Show,
        :console
      )

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/settingz",
        Live.Devices.Show,
        :settings
      )

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/health",
        Live.Devices.DeviceHealth
      )

      live(
        "/org/:org_name/:product_name/devices/:device_identifier/settings",
        Live.Devices.Settings
      )

      live("/org/:org_name/:product_name/firmware", Live.Firmware, :index)
      live("/org/:org_name/:product_name/firmware/upload", Live.Firmware, :upload)
      live("/org/:org_name/:product_name/firmware/:firmware_uuid", Live.Firmware, :show)

      live("/org/:org_name/:product_name/archives", Live.Archives, :index)
      live("/org/:org_name/:product_name/archives/upload", Live.Archives, :upload)
      live("/org/:org_name/:product_name/archives/:archive_uuid", Live.Archives, :show)

      live("/org/:org_name/:product_name/deployments", Live.Deployments.Index)
      live("/org/:org_name/:product_name/deployments/new", Live.Deployments.New)
      live("/org/:org_name/:product_name/deployments/:name", Live.Deployments.Show)
      live("/org/:org_name/:product_name/deployments/:name/edit", Live.Deployments.Edit)

      live("/org/:org_name/:product_name/scripts", Live.SupportScripts.Index)
      live("/org/:org_name/:product_name/scripts/new", Live.SupportScripts.New)
      live("/org/:org_name/:product_name/scripts/:script_id/edit", Live.SupportScripts.Edit)

      live("/org/:org_name/:product_name/settings", Live.Product.Settings)
    end
  end

  scope "/" do
    pipe_through([:browser, :logged_in, NervesHubWeb.Plugs.ServerAuth])
    live_dashboard("/status/dashboard")
    oban_dashboard("/status/oban", resolver: NervesHubWeb.Plugs.ServerAuth)
  end

  if Mix.env() == :dev do
    forward("/mailbox", Plug.Swoosh.MailboxPreview)
  end
end
