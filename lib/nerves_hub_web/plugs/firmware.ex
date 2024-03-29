defmodule NervesHubWeb.Plugs.Firmware do
  use NervesHubWeb, :plug

  alias NervesHub.Firmwares

  def init(opts) do
    opts
  end

  def call(
        %{params: %{"firmware_uuid" => firmware_uuid}, assigns: %{product: product}} = conn,
        _opts
      ) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, firmware_uuid) do
      conn
      |> assign(:firmware, firmware)
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
