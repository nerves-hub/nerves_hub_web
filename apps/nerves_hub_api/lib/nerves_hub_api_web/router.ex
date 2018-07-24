defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", NervesHubAPIWeb do
    pipe_through :api
  end
end
