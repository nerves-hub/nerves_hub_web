defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug NervesHubAPIWeb.Plugs.User
  end

  scope "/", NervesHubAPIWeb do
    pipe_through :api

    get "/users/me", UserController, :me
  end

end
