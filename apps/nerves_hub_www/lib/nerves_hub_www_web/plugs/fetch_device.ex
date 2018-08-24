defmodule NervesHubWWWWeb.Plugs.FetchDevice do
  import Plug.Conn

  alias NervesHubCore.Devices

  def init(opts) do
    opts
  end

  def call(
        %{assigns: %{org: org}, params: %{"device" => %{"id" => device_id}}} = conn,
        _opts
      ) do
    org
    |> Devices.get_device_by_org(device_id)
    |> case do
      {:ok, device} ->
        conn
        |> assign(:device, device)

      _ ->
        conn
        |> halt()
    end
  end
end
