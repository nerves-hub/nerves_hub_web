defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :user do
    plug(NervesHubAPIWeb.Plugs.User)
  end

  pipeline :org do
    plug(NervesHubAPIWeb.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubAPIWeb.Plugs.Product)
  end

  pipeline :device do
    plug(NervesHubAPIWeb.Plugs.Device)
  end

  scope "/health", NervesHubAPIWeb do
    pipe_through(:api)

    get("/", HealthCheckController, :health_check)
  end

  scope "/users", NervesHubAPIWeb do
    pipe_through(:api)

    post("/register", UserController, :register)
    post("/auth", UserController, :auth)
    post("/login", UserController, :login)
    post("/sign", UserController, :sign)
  end

  scope "/", NervesHubAPIWeb do
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

        scope "/jitp" do
          get("/:ski", JITPController, :show)
        end

        # The /org/:org_id/device* endpoints should return an error
        scope "/devices" do
          get("/", DeviceController, :error_deprecated)
          post("/", DeviceController, :error_deprecated)
          post("/auth", DeviceController, :error_deprecated)

          scope "/:device_identifier" do
            get("/", DeviceController, :error_deprecated)
            delete("/", DeviceController, :error_deprecated)
            put("/", DeviceController, :error_deprecated)

            scope "/certificates" do
              get("/", DeviceController, :error_deprecated)
              post("/sign", DeviceController, :error_deprecated)
            end
          end
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

                scope "/certificates" do
                  get("/", DeviceCertificateController, :index)
                  get("/:serial", DeviceCertificateController, :show)
                  post("/", DeviceCertificateController, :create)
                  post("/sign", DeviceCertificateController, :sign)
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
