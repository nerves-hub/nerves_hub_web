defmodule NervesHubWeb.Live.Deployments.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Fixtures

  test "no deployments", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployments")
    |> assert_has("h3", text: "#{product.name} doesn’t have any deployments configured")
  end

  test "has deployments", %{conn: conn, org: org, product: product, deployment: deployment} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployments")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
    |> assert_has("td div", text: "0")
  end

  test "device counts don't include deleted devices", %{
    conn: conn,
    org: org,
    product: product,
    deployment: deployment,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployments")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
    |> assert_has("td div", text: "0")

    Deployments.set_deployment(device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployments")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
    |> assert_has("td div", text: "1")

    Devices.delete_device(device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployments")
    |> assert_has("h1", text: "Deployments")
    |> assert_has("a", text: deployment.name)
    |> assert_has("td div", text: "0")
  end
end
