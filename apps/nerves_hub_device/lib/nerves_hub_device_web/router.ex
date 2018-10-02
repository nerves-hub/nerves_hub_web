defmodule NervesHubDeviceWeb.Router do
  use NervesHubDeviceWeb, :router

  pipeline :device do
    plug(NervesHubDeviceWeb.Plugs.Device)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Other scopes may use custom stacks.
  scope "/", NervesHubDeviceWeb do
    pipe_through(:api)
    pipe_through(:device)

    scope "/device" do
      get("/me", DeviceController, :me)
      get("/update", DeviceController, :update)
    end
  end
end
