defmodule NervesHubWeb.Router do
  use NervesHubWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html", "json"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {NervesHubWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(NervesHubWeb.Plugs.SetLocale)
  end

  pipeline :logged_in do
    plug(NervesHubWeb.Plugs.FetchUser)
    plug(NervesHubWeb.Plugs.EnsureLoggedIn)
  end

  pipeline :live_logged_in do
    plug(NervesHubWeb.Plugs.EnsureAuthenticated)
  end

  pipeline :admins_only do
    plug(NervesHubWeb.Plugs.AdminBasicAuth)
  end

  pipeline :product do
    plug(NervesHubWeb.Plugs.Product)
  end

  pipeline :firmware do
    plug(NervesHubWeb.Plugs.Firmware)
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

  scope "/products/:hashid", NervesHubWeb do
    pipe_through([:browser, :logged_in, :product])

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
    pipe_through([:browser, :live_logged_in])

    live_session :account,
      on_mount: [
        NervesHubWeb.Mounts.AccountAuth,
        NervesHubWeb.Mounts.CurrentPath
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
        NervesHubWeb.Mounts.FetchOrgUser
      ] do
      live("/orgs/:hashid", Live.Org.Products, :index)
      live("/orgs/:hashid/new", Live.Org.Products, :new)
      live("/orgs/:hashid/settings", Live.Org.Settings)
      live("/orgs/:hashid/settings/keys", Live.Org.SigningKeys, :index)
      live("/orgs/:hashid/settings/keys/new", Live.Org.SigningKeys, :new)
      live("/orgs/:hashid/settings/users", Live.Org.Users, :index)
      live("/orgs/:hashid/settings/users/invite", Live.Org.Users, :invite)
      live("/orgs/:hashid/settings/users/:user_id/edit", Live.Org.Users, :edit)
      live("/orgs/:hashid/settings/certificates", Live.Org.CertificateAuthorities, :index)
      live("/orgs/:hashid/settings/certificates/new", Live.Org.CertificateAuthorities, :new)
      live("/orgs/:hashid/settings/delete", Live.Org.Delete)

      live(
        "/orgs/:hashid/settings/certificates/:serial/edit",
        Live.Org.CertificateAuthorities,
        :edit
      )
    end

    live_session :product,
      on_mount: [
        NervesHubWeb.Mounts.AccountAuth,
        NervesHubWeb.Mounts.CurrentPath,
        NervesHubWeb.Mounts.FetchProduct,
        NervesHubWeb.Mounts.FetchOrgUser
      ] do
      live("/products/:hashid/devices", Live.Devices.Index)
      live("/products/:hashid/devices/new", Live.Devices.New)
      live("/products/:hashid/devices/:device_identifier", Live.Devices.Show)
      live("/products/:hashid/devices/:device_identifier/edit", Live.Devices.Edit)

      live("/products/:hashid/firmware", Live.Firmware, :index)
      live("/products/:hashid/firmware/upload", Live.Firmware, :upload)
      live("/products/:hashid/firmware/:firmware_uuid", Live.Firmware, :show)

      live("/products/:hashid/archives", Live.Archives, :index)
      live("/products/:hashid/archives/upload", Live.Archives, :upload)
      live("/products/:hashid/archives/:archive_uuid", Live.Archives, :show)

      live("/products/:hashid/deployments", Live.Deployments.Index)
      live("/products/:hashid/deployments/new", Live.Deployments.New)
      live("/products/:hashid/deployments/:name", Live.Deployments.Show)
      live("/products/:hashid/deployments/:name/edit", Live.Deployments.Edit)

      live("/products/:hashid/scripts", Live.SupportScripts.Index)
      live("/products/:hashid/scripts/new", Live.SupportScripts.New)
      live("/products/:hashid/scripts/:script_id/edit", Live.SupportScripts.Edit)

      live("/products/:hashid/settings", Live.Product.Settings)
    end
  end

  if Mix.env() in [:dev] do
    scope "/dev" do
      pipe_through([:browser])

      forward("/mailbox", Plug.Swoosh.MailboxPreview)
      live_dashboard("/dashboard")
    end
  else
    scope "/" do
      pipe_through([:browser, :admins_only])
      live_dashboard("/status/dashboard")
    end
  end
end
