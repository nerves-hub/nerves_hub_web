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

  pipeline :org do
    plug(NervesHubWeb.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubWeb.Plugs.Product)
  end

  pipeline :device do
    plug(NervesHubWeb.Plugs.Device)
  end

  pipeline :deployment do
    plug(NervesHubWeb.Plugs.Deployment)
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

    post("/users/register", UserController, :register)
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
            get("/:username", OrgUserController, :show)
            put("/:username", OrgUserController, :update)
            delete("/:username", OrgUserController, :remove)
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
        NervesHubWeb.Mounts.FetchProduct
      ] do
      live("/org/:org_name/:product_name/settings", Live.Product.Settings)
    end
  end

  scope "/", NervesHubWeb do
    pipe_through([:browser, :logged_in])

    scope "/org/:org_name" do
      pipe_through(:org)

      scope "/:product_name" do
        pipe_through(:product)

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
            post("/reboot", DeviceController, :reboot)
            post("/toggle-updates", DeviceController, :toggle_updates)
            get("/certificate/:cert_serial/download", DeviceController, :download_certificate)
            get("/audit_logs/download", DeviceController, :export_audit_logs)
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

        resources("/archives", ArchiveController,
          only: [:index, :show, :new, :create, :delete],
          param: "uuid"
        )

        resources("/scripts", ScriptController)

        get("/archives/:uuid/download", ArchiveController, :download)

        scope "/deployments" do
          get("/", DeploymentController, :index)
          post("/", DeploymentController, :create)
          get("/new", DeploymentController, :new)

          scope "/:deployment_name" do
            pipe_through(:deployment)

            get("/", DeploymentController, :show)
            get("/edit", DeploymentController, :edit)
            patch("/", DeploymentController, :update)
            put("/", DeploymentController, :update)
            post("/toggle", DeploymentController, :toggle)
            delete("/", DeploymentController, :delete)
            get("/audit_logs/download", DeploymentController, :export_audit_logs)
          end
        end
      end
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
