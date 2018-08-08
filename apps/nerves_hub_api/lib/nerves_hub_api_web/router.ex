defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug NervesHubAPIWeb.Plugs.User
    plug NervesHubCore.Plugs.Product
  end

  scope "/", NervesHubAPIWeb do
    pipe_through :api

    scope "/users" do
      get "/me", UserController, :me
    end
    
    post "/firmwares", FirmwareController, :create
    
    scope "/firmwares" do
      get("/", FirmwareController, :index)
      get("/:uuid", FirmwareController, :show)
      delete("/:uuid", FirmwareController, :delete)
    end

    scope "/deployments" do
      get("/", DeploymentController, :index)
      get("/:name", DeploymentController, :show)
      put("/:name", DeploymentController, :update)
    end
  end
end
