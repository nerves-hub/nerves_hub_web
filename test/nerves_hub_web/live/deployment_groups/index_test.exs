defmodule NervesHubWeb.Live.DeploymentGroups.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  test "no deployment groups", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h3", text: "#{product.name} doesn’t have any deployments configured")
  end

  test "has deployment groups", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td div", text: "0")
  end

  test "device counts don't include deleted devices", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td div", text: "0")

    ManagedDeployments.set_deployment_group(device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td div", text: "1")

    Devices.delete_device(device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td div", text: "0")
  end
end
