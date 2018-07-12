defmodule NervesHubWeb.Plugs.Api.AuthenticateDevice do
  import Plug.Conn

  alias NervesHubCore.Devices
  alias NervesHubCore.Devices.Device
  alias Phoenix.Controller
  alias NervesHubWeb.Api.ErrorView

  def init(_), do: nil

  def call(%{req_headers: headers} = conn, _) do
    headers
    |> Enum.find(fn
      {"x-client-dn", "CN=" <> _} -> true
      _ -> false
    end)
    |> case do
      nil ->
        {:error, :header_missing}

      {"x-client-dn", "CN=" <> identifier} ->
        Devices.get_device_by_identifier(identifier)
    end
    |> case do
      {:ok, %Device{} = device} ->
        conn
        |> assign(:device, device)

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> Controller.put_view(ErrorView)
        |> Controller.render("error.json", %{error: "unauthorized"})
        |> halt()
    end
  end
end
