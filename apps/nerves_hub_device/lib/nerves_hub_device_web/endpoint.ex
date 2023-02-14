defmodule NervesHubDeviceWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub_device
  use SpandexPhoenix

  socket(
    "/socket",
    NervesHubDeviceWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers]
    ]
  )

  plug(NervesHubDeviceWeb.Plugs.Logger)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  @impl Phoenix.Endpoint
  def init(_key, config) do
    config = verify_fun(config)

    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end

  defp verify_fun(config) do
    if https_opts = Keyword.get(config, :https) do
      https_opts = Keyword.put(https_opts, :verify_fun, {&NervesHubDevice.SSL.verify_fun/3, nil})
      Keyword.put(config, :https, https_opts)
    else
      config
    end
  end
end
