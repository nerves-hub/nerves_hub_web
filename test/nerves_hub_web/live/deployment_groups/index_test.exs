defmodule NervesHubWeb.Live.DeploymentGroups.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHubWeb.Components.ListSettingsSidebar

  test "no deployment groups", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("span", text: "#{product.name} doesn’t have any deployment groups configured.")
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
    |> assert_has("td", text: "0")
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
    |> assert_has("td", text: "0")

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td", text: "1")

    Devices.delete_device(device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
    |> assert_has("h1", text: "Deployment Groups")
    |> assert_has("a", text: deployment_group.name)
    |> assert_has("td", text: "0")
  end

  describe "filtering" do
    test "filter deployment groups on name", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
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
      platform = deployment_group.current_release.firmware.platform

      conn
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
      architecture = deployment_group.current_release.firmware.architecture

      conn
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

  describe "customize columns listed" do
    test "all columns are shown, as the default", %{conn: conn, fixture: fixture} do
      %{user: user} = fixture

      assert is_nil(user.display_preferences)

      conn
      |> visit("/org/#{fixture.org.name}/#{fixture.product.name}/deployment_groups")
      |> assert_has("th", text: "Platform")
      |> assert_has("th", text: "Architecture")
      |> assert_has("th", text: "Devices")
      |> assert_has("th", text: "Releases")
      |> assert_has("th", text: "Firmware version")
      |> assert_has("th", text: "Device Tags")
      |> assert_has("th", text: "Version Constraint")
    end

    for {column, label} <- [
          {:platform, "Platform"},
          {:architecture, "Architecture"},
          {:device_count, "Devices"},
          {:release_count, "Releases"},
          {:firmware_version, "Firmware version"},
          {:tags, "Tags"},
          {:version_constraint, "Version Constraint"}
        ] do
      @column column
      @label label
      @friendly_column_name to_string(@column) |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

      test "#{column} column can be removed", %{conn: conn, fixture: fixture} do
        %{user: user} = fixture

        assert is_nil(user.display_preferences)

        conn
        |> visit("/org/#{fixture.org.name}/#{fixture.product.name}/deployment_groups")
        |> assert_has("th", text: @label)
        |> click_button("#deployment-groups-container button[phx-click=toggle-settings]", "")
        |> uncheck(@friendly_column_name)
        |> refute_has("th", text: @label, timeout: 1_000)
      end

      test "#{column} column can be added", %{conn: conn, fixture: %{user: user} = fixture} do
        assert is_nil(user.display_preferences)

        default_column_payload = %{
          "_target" => [to_string(@column)],
          "architecture" => true,
          "device_count" => true,
          "firmware_version" => true,
          "platform" => true,
          "release_count" => true,
          "tags" => true,
          "version_constraint" => true
        }

        {:ok, _user} =
          ListSettingsSidebar.update_displayed_columns(
            user,
            :deployment_group_list_columns,
            Map.put(default_column_payload, to_string(@column), "false")
          )

        conn
        |> visit("/org/#{fixture.org.name}/#{fixture.product.name}/deployment_groups")
        |> refute_has("th", text: @label)
        |> click_button("#deployment-groups-container button[phx-click=toggle-settings]", "")
        |> check(@friendly_column_name)
        |> assert_has("th", text: @label, timeout: 1_000)
      end
    end
  end

  describe "sorting" do
    test "renders the list with a non-default sort column", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups?sort=platform&sort_direction=desc")
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
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups")
      |> refute_has("button", text: "25", timeout: 1000)
    end

    test "pagination with more than 25 deployment groups", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      for i <- 1..26 do
        Fixtures.deployment_group_fixture(deployment_group.current_release.firmware, %{
          name: "Deployment-group-#{i}",
          user: user
        })
      end

      deployment_groups = ManagedDeployments.get_deployment_groups_by_product(product)
      [first_deployment_group | _] = deployment_groups |> Enum.sort_by(& &1.name)

      conn
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
