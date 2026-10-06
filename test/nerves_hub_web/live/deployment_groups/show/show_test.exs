defmodule NervesHubWeb.Live.DeploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.Fixtures
  alias NervesHub.Helpers.Logging
  alias NervesHub.Repo

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
      {:ok, %{updated: 1}}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
  end

  test "remove-unmatched-devices keeps matching devices without reporting them as failures", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    kept_one = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})
    kept_two = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})
    removed = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"], deployment_id: deployment_group.id})

    reject(Logging, :log_to_sentry, 3)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
    |> refute_has("div", text: "couldn't remove", exact: false)

    assert Repo.reload(kept_one).deployment_id == deployment_group.id
    assert Repo.reload(kept_two).deployment_id == deployment_group.id
    refute Repo.reload(removed).deployment_id
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

  describe "a user who can only view" do
    setup %{org: org, user: user} do
      {1, _} =
        OrgUser
        |> where([ou], ou.org_id == ^org.id and ou.user_id == ^user.id)
        |> Repo.update_all(set: [role: :view])

      :ok
    end

    test "cannot move matching devices into the deployment group", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
        |> assert_has("span", text: "match outside of deployment group", exact: false)
        |> refute_has("button", text: "Move device")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "move-matched-devices-to-deployment-group", %{}))

      refute Repo.reload(device).deployment_id
    end

    test "cannot remove unmatched devices from the deployment group", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"], deployment_id: deployment_group.id})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
        |> assert_has("span", text: "match inside deployment group", exact: false)
        |> refute_has("button", text: "Remove device")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "remove-unmatched-devices-from-deployment-group", %{}))

      assert Repo.reload(device).deployment_id == deployment_group.id
    end

    test "cannot import devices from a CSV", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("div", text: "Device Matching Conditions")
      |> refute_has("label", text: "Import from CSV")
    end
  end
end
