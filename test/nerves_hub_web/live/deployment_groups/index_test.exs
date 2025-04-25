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

  describe "filtering" do
    test "filter deployment groups on name", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> assert_has("h1", text: "Deployment Groups")
      |> assert_has("a", text: deployment_group.name)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"name" => deployment_group.name})
      end)
      |> assert_has("a", text: deployment_group.name)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"name" => "blah"})
      end)
      |> refute_has("a", text: deployment_group.name)
    end

    test "filter deployment groups on platform", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      platform = deployment_group.firmware.platform

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> assert_has("td", text: platform)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"platform" => platform})
      end)
      |> assert_has("td", text: platform)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"platform" => "blah"})
      end)
      |> refute_has("td", text: platform)
    end

    test "filter deployment groups on architecture", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      architecture = deployment_group.firmware.architecture

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> assert_has("td", text: architecture)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"architecture" => architecture})
      end)
      |> assert_has("td", text: architecture)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"architecture" => "blah"})
      end)
      |> refute_has("td", text: architecture)
    end

    test "reset filters", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> assert_has("a", text: deployment_group.name)
      |> unwrap(fn view ->
        render_change(view, "update-filters", %{"name" => "blah"})
      end)
      |> refute_has("a", text: deployment_group.name)
      |> unwrap(fn view ->
        render_change(view, "reset-filters", %{})
      end)
      |> assert_has("a", text: deployment_group.name)
    end
  end

  describe "pagination" do
    test "no pagination when less than 25 deployment groups", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> refute_has("button", text: "25", timeout: 1000)
    end

    test "pagination with more than 25 deployment groups", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      for i <- 1..26 do
        Fixtures.deployment_group_fixture(org, deployment_group.firmware, %{
          name: "Deployment-group-#{i}"
        })
      end

      deployment_groups = ManagedDeployments.get_deployment_groups_by_product(product)
      [first_deployment_group | _] = deployment_groups |> Enum.sort_by(& &1.name)

      conn
      |> put_session("new_ui", true)
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> assert_has("a", text: first_deployment_group.name, timeout: 1000)
      |> assert_has("button", text: "25", timeout: 1000)
      |> assert_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_deployment_group.name, timeout: 1000)
    end
  end
end
