defmodule NervesHubWeb.API.Plugs.Device do
  import Plug.Conn

  alias NervesHub.Devices

  def init(opts) do
    opts
  end

  def call(%{params: %{"identifier" => identifier}} = conn, _opts) do
    case Devices.get_device_by_identifier(conn.assigns.org, identifier) do
      {:ok, device} ->
        conn
        |> assign(:device, device)

      _ ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "Invalid device: #{identifier}"}))
        |> halt()
    end
  end
end
