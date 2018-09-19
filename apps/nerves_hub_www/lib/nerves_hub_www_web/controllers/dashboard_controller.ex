defmodule NervesHubWWWWeb.DashboardController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products
  alias NervesHubCore.Devices

  def index(%{assigns: %{current_org: org}} = conn, _params) do
    org = NervesHubCore.Repo.preload(org, devices: [:last_known_firmware], products: [])
    stats = NervesHubWWW.Statistics.devices_per_product(org)

    conn
    |> render("index.html", products: org.products, stats: stats)
  end

  def show(%{assigns: %{current_org: org}} = conn, %{"id" => id}) do
    org = NervesHubCore.Repo.preload(org, [:devices, :products])
    product = Products.get_product!(id) |> NervesHubCore.Repo.preload(:firmwares)

    stats = NervesHubWWW.Statistics.devices_per_firmware(org, product)

    render(conn, "show.html", products: org.products, product: product, stats: stats)
  end
end
