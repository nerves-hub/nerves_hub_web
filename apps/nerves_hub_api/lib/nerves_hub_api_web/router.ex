defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :authenticated do
    plug(NervesHubAPIWeb.Plugs.User)
    plug(NervesHubCore.Plugs.Product)
  end

  scope "/users", NervesHubAPIWeb do
    pipe_through(:api)

    post("/register", UserController, :register)
    post("/auth", UserController, :auth)
    post("/sign", UserController, :sign)
  end

  scope "/", NervesHubAPIWeb do
    pipe_through(:api)
    pipe_through(:authenticated)

    scope "/users" do
      get("/me", UserController, :me)
    end

    post("/firmwares", FirmwareController, :create)

    scope "/firmwares" do
      get("/", FirmwareController, :index)
      get("/:uuid", FirmwareController, :show)

      delete("/:uuid", FirmwareController, :delete)
    end

    scope "/keys" do
      get("/", KeyController, :index)
      post("/", KeyController, :create)
      get("/:name", KeyController, :show)
      delete("/:name", KeyController, :delete)
    end

    scope "/deployments" do
      get("/", DeploymentController, :index)
      get("/:name", DeploymentController, :show)
      put("/:name", DeploymentController, :update)
    end
  end
end
