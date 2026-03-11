defmodule NervesHubWeb.ProductController do
  use NervesHubWeb, :controller

  alias NervesHub.Products

  plug(:validate_role, [org: :view] when action in [:devices_export])

  def devices_export(%{assigns: %{current_scope: scope}} = conn, _params) do
    filename = "#{scope.product.name}-devices.csv"
    send_download(conn, {:binary, Products.devices_csv(scope.product)}, filename: filename)
  end
end
