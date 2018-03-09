defmodule BeamwareWeb.Plugs.Api.AuthenticateDevice do
  import Plug.Conn

  alias Beamware.Devices
  alias Beamware.Devices.Device

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
        |> halt()
    end
  end
end
