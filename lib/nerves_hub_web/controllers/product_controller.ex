defmodule NervesHubWeb.ProductController do
  use NervesHubWeb, :controller

  alias NervesHub.Products

  action_fallback(NervesHubWeb.FallbackController)

  plug(:validate_role, [org: :view] when action in [:devices_export])

  def devices_export(%{assigns: %{product: product}} = conn, _params) do
    filename = "#{product.name}-devices.csv"
    send_download(conn, {:binary, Products.devices_csv(product)}, filename: filename)
  end
end
