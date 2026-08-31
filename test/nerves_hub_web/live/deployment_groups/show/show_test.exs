defmodule NervesHubWeb.Live.DeploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.Fixtures
  alias NervesHub.Helpers.Logging

  setup %{
          conn: conn,
          user: user,
          org: org,
          product: product,
          org_key: org_key,
          tmp_dir: tmp_dir
        } = context do
    firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{
        is_active: true,
        name: "ShowTest Deployment",
        conditions: %{"version" => "<= 1.0.0", "tags" => ["beta"], "tag_operator" => "or"},
        user: user
      })

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("h1", text: deployment_group.name)

    Map.merge(context, %{
      conn: conn,
      firmware: firmware,
      deployment_group: deployment_group
    })
  end

  test "handle_info :update_inflight_updates while on summary tab", %{conn: conn} do
    conn
    |> unwrap(fn view ->
      send(view.pid, :update_inflight_updates)
      render(view)
    end)
    |> assert_has("h1", exact: false)
  end

  test "handle_info :update_inflight_updates on non-summary tab does not crash", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
    |> unwrap(fn view ->
      send(view.pid, :update_inflight_updates)
      render(view)
    end)
  end

  test "move-matched-devices exit path shows flash error", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _ -> :ok end)

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      raise "simulated async exit"
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "There was an issue moving devices to #{deployment_group.name}",
      timeout: 1000
    )
  end

  test "move-matched-devices success path shows count in flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      %{updated: 1, ignored: 0}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "1 devices moved to #{deployment_group.name}",
      timeout: 1000
    )
  end

  test "move-matched-devices partial success shows partial error flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _, _ -> :ok end)

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      %{updated: 0, ignored: 1}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "couldn't move 1 devices",
      exact: false,
      timeout: 1000
    )
  end

  test "remove-unmatched-devices success path shows count in flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Deployments, :remove_unmatched_devices_from_deployment_group, fn _, _ ->
      {:ok, %{updated: 1, ignored: 0}}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
  end

  test "remove-unmatched-devices partial success shows partial error flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _, _ -> :ok end)

    stub(Deployments, :remove_unmatched_devices_from_deployment_group, fn _, _ ->
      {:ok, %{updated: 0, ignored: 1}}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div",
      text: "couldn't remove 1 devices",
      exact: false,
      timeout: 1000
    )
  end

  test "remove-unmatched-devices exit path shows flash error", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _ -> :ok end)

    stub(Deployments, :remove_unmatched_devices_from_deployment_group, fn _, _ ->
      raise "simulated async exit"
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div",
      text: "There was an issue removing devices from #{deployment_group.name}",
      timeout: 1000
    )
  end
end
