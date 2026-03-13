defmodule NervesHubWeb.API.Plugs.GlobalUniqueDeviceIdentifiersRequired do
  use NervesHubWeb, :plug

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case Application.get_env(:nerves_hub, :platform_unique_device_identifiers) do
      true ->
        conn

      false ->
        raise NervesHubWeb.RequiresGlobalUniqueIdentifiersError
    end
  end
end
