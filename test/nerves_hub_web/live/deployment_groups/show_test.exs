defmodule NervesHubWeb.Live.DeploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  alias NervesHub.Repo

  test "shows the deployment group", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("p.deployment-group-state", text: "Off")
    |> assert_has("div#device-count p", text: "0")
    |> then(fn conn ->
      for tag <- deployment_group.conditions["tags"] do
        assert_has(conn, "span", text: tag)
      end

      conn
    end)
  end

  test "shows the deployment group with device count", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    device: device,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)
    %Device{} = Devices.update_deployment_group(device, deployment_group)

    # deleted devices shouldn't be included in the count
    device_2 = Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})
    %Device{} = Devices.update_deployment_group(device_2, deployment_group)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("p.deployment-group-state", text: "Off")
    |> assert_has("div#device-count p", text: "1")
    |> then(fn conn ->
      for tag <- deployment_group.conditions["tags"] do
        assert_has(conn, "span", text: tag)
      end

      conn
    end)
  end

  test "you can delete a deployment group with no devices attached to it", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("h1", text: deployment_group.name)
    |> click_link("Delete")
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups"))
    |> assert_has("div", text: "Deployment Group successfully deleted")

    assert ManagedDeployments.get_deployment_group(product, deployment_group.id) ==
             {:error, :not_found}

    logs = AuditLogs.logs_for(deployment_group)

    assert List.last(logs).description =~ ~r/deleted deployment/
  end

  test "you can delete a deployment group with devices attached to it", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)
    device = Fixtures.device_fixture(org, product, firmware)

    device = Devices.update_deployment_group(device, deployment_group)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("h1", text: deployment_group.name)
    |> click_link("Delete")
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups"))
    |> assert_has("div", text: "Deployment Group successfully deleted")

    assert ManagedDeployments.get_deployment_group(product, deployment_group.id) ==
             {:error, :not_found}

    logs = AuditLogs.logs_for(deployment_group)

    assert List.last(logs).description =~ ~r/deleted deployment/

    device = Repo.reload(device)
    assert device.deployment_id == nil
    assert device.deleted_at == nil
  end

  test "you can toggle the deployment group being on or off", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("h1", text: deployment_group.name)
    |> click_link("Turn On")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment_group} =
        ManagedDeployments.get_deployment_group(product, deployment_group.id)

      assert reloaded_deployment_group.is_active
      assert_has(conn, "span", text: "Turn Off")

      logs = AuditLogs.logs_for(deployment_group)
      assert Enum.count(logs) == 1
      assert List.last(logs).description =~ ~r/marked deployment/
      conn
    end)
    |> click_link("Turn Off")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment_group} =
        ManagedDeployments.get_deployment_group(product, deployment_group.id)

      refute reloaded_deployment_group.is_active
      assert_has(conn, "span", text: "Turn On")

      logs = AuditLogs.logs_for(reloaded_deployment_group)
      assert Enum.count(logs) == 3
      assert List.last(logs).description =~ ~r/marked deployment/
      conn
    end)
  end

  test "displays text when every device in deployment group matches conditions", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    _device1 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["beta"]
      })

    _device2 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["beta-edge"]
      })

    conn
    |> put_session("new_ui", true)
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "100% of devices in this deployment group match conditions")
  end

  test "removing device from deployment that doesn't match conditions", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    device1 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["foo"]
      })

    _device2 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["beta-edge"]
      })

    conn
    |> put_session("new_ui", true)
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "50% of devices in this deployment group match conditions")
    |> assert_has("div", text: "1 device doesn't match inside deployment group")
    |> click_button("Remove device")
    |> assert_has("span",
      text: "100% of devices in this deployment group match conditions",
      timeout: 1
    )
    |> then(fn _ ->
      refute Repo.reload(device1) |> Map.get(:deployment_id)
    end)
  end

  test "adding devices from outside deployment that matches conditions", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    device1 =
      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["beta"]
      })

    _device2 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["beta-edge"]
      })

    conn
    |> put_session("new_ui", true)
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "100% of devices in this deployment group match conditions")
    |> assert_has("div", text: "1 device matches outside of deployment group")
    |> click_button("Move device")
    |> assert_has("span",
      text: "100% of devices in this deployment group match conditions",
      timeout: 1
    )
    |> then(fn _ ->
      assert Repo.reload(device1) |> Map.get(:deployment_id)
    end)
  end
end
