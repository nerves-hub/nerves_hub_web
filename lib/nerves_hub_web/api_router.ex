defmodule NervesHubWeb.APIRouter do
  use NervesHubWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :user do
    plug(NervesHubWeb.API.Plugs.User)
  end

  pipeline :org do
    plug(NervesHubWeb.API.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubWeb.API.Plugs.Product)
  end

  pipeline :device do
    plug(NervesHubWeb.API.Plugs.Device)
  end

  scope "/health", NervesHubWeb.API do
    pipe_through(:api)

    get("/", HealthCheckController, :health_check)
  end

  scope "/users", NervesHubWeb.API do
    pipe_through(:api)

    post("/register", UserController, :register)
    post("/auth", UserController, :auth)
    post("/login", UserController, :login)
  end

  scope "/", NervesHubWeb.API do
    pipe_through(:api)
    pipe_through(:user)

    scope "/users" do
      get("/me", UserController, :me)
    end

    scope "/orgs" do
      scope "/:org_name" do
        pipe_through(:org)

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
            pipe_through(:product)

            get("/", ProductController, :show)
            delete("/", ProductController, :delete)
            put("/", ProductController, :update)

            scope "/devices" do
              get("/", DeviceController, :index)
              post("/", DeviceController, :create)
              post("/auth", DeviceController, :auth)

              scope "/:device_identifier" do
                pipe_through(:device)
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

            scope "/users" do
              get("/", ProductUserController, :index)
              post("/", ProductUserController, :add)
              get("/:username", ProductUserController, :show)
              put("/:username", ProductUserController, :update)
              delete("/:username", ProductUserController, :remove)
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
