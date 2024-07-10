defmodule NervesHubWeb.Plugs.Device do
  use NervesHubWeb, :plug

  alias NervesHub.Devices

  def init(opts) do
    opts
  end

  def call(
        %{params: %{"identifier" => device_identifier}, assigns: %{org: org}} = conn,
        _opts
      ) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, device_identifier) do
      conn
      |> assign(:device, device)
    else
      _error ->
        conn
        |> put_status(:not_found)
        |> put_view(NervesHubWeb.ErrorView)
        |> render("404.html")
        |> halt
    end
  end
end
