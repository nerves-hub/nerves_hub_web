defmodule NervesHubDeviceWeb.Router do
  use NervesHubDeviceWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Other scopes may use custom stacks.
  scope "/", NervesHubDeviceWeb do
    pipe_through :api
  end
end
