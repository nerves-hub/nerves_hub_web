defmodule NervesHubWeb.Live.DeploymentGroups.Show.SummaryTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Firmwares.Upload.File
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup %{
          conn: conn,
          org: org,
          product: product,
          org_key: org_key,
          tmp_dir: tmp_dir,
          fixture: %{firmware: source_firmware}
        } =
          context do
    target_firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(target_firmware, %{
        is_active: true,
        name: "Coolest Deployment"
      })

    device =
      Fixtures.device_fixture(org, product, source_firmware, %{status: :provisioned})
      |> Devices.update_deployment_group(deployment_group)

    # Ensure device firmware metadata reflects the target firmware because
    # update stats are logged after a successful firmware update
    {:ok, target_metadata} = Firmwares.metadata_from_firmware(target_firmware)

    {:ok, device} =
      Devices.update_firmware_metadata(device, target_metadata, :unknown, false)

    {:ok, source_firmware_metadata} = Firmwares.metadata_from_firmware(source_firmware)

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("div", text: "Current Release")
      |> assert_has("div", text: "Settings Overview")

    Map.merge(context, %{
      conn: conn,
      device: device,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      source_firmware_metadata: source_firmware_metadata
    })
  end

  test "empty state and displaying update stats", %{
    conn: conn,
    device: device,
    source_firmware_metadata: source_firmware_metadata,
    target_firmware: target_firmware
  } do
    conn =
      conn
      |> assert_has("span", text: "No stats recorded for", exact: false)

    :ok = UpdateStats.log_update(device, source_firmware_metadata)

    conn
    |> refute_has("span",
      text: "No stats recorded for",
      exact: false,
      timeout: 100
    )
    |> assert_has("div", text: source_firmware_metadata.version)
    |> assert_has("span", text: "Update count:")
    |> assert_has("span", text: "1")
    |> assert_has("span", text: "Total updates size:")
    |> assert_has("span", text: "#{target_firmware.size} B")
    |> assert_has("span", text: "Delta update savings:")
    |> assert_has("span", text: "0 B")
    |> assert_has("span", text: "Average size per device:")
    |> assert_has("span", text: "#{target_firmware.size} B")
    |> assert_has("span", text: "Average saved per device:")
    |> assert_has("span", text: "0 B")
  end

  test "delta updates show savings", %{
    conn: conn,
    device: device,
    source_firmware_metadata: source_firmware_metadata,
    source_firmware: source_firmware,
    target_firmware: target_firmware
  } do
    :ok = UpdateStats.log_update(device, source_firmware_metadata)
    delta = Fixtures.firmware_delta_fixture(source_firmware, target_firmware)
    :ok = UpdateStats.log_update(device, source_firmware_metadata)

    conn
    |> assert_has("div", text: source_firmware_metadata.version)
    |> assert_has("span", text: "Update count:")
    |> assert_has("span", text: "2")
    |> assert_has("span", text: "Delta update savings:")
    |> assert_has("span", text: "#{target_firmware.size - delta.size} B")
  end

  test "view stats of deployment's firmware versions", %{
    conn: conn,
    device: device,
    source_firmware_metadata: source_firmware_metadata,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir,
    user: user
  } do
    :ok = UpdateStats.log_update(device, source_firmware_metadata)

    other_firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "2.0.1", dir: tmp_dir})

    {:ok, other_firmware_metadata} = Firmwares.metadata_from_firmware(other_firmware)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{
          firmware_id: other_firmware.id
        },
        user
      )

    # deployment group needs to be explicitly passed in because association
    # is already preloaded from fixtures, causing the preload in log_update/2
    # to noop
    #
    # update twice so we can assert confidently
    for _ <- 1..2,
        do:
          UpdateStats.log_update(
            %{
              device
              | firmware_metadata: other_firmware_metadata,
                deployment_group: deployment_group
            },
            source_firmware_metadata
          )

    conn
    |> assert_has("option[selected]", text: other_firmware.version)
    |> assert_has("span", text: "Update count:")
    |> assert_has("span", text: "2")
  end

  test "shows delta status and available actions", %{
    conn: conn,
    source_firmware: source_firmware,
    target_firmware: target_firmware,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

    conn
    |> assert_has("div", text: "Processing", timeout: 100)
    |> refute_has("a", text: "Delete")
    |> refute_has("a", text: "Retry")

    {:ok, delta} = Firmwares.fail_firmware_delta(delta)

    conn
    |> assert_has("div", text: "Failed", timeout: 100)
    |> assert_has("a", text: "Delete")
    |> assert_has("a", text: "Retry")

    {:ok, delta} = Firmwares.time_out_firmware_delta(delta)

    conn
    |> assert_has("div", text: "Timed out", timeout: 100)
    |> assert_has("a", text: "Delete")
    |> assert_has("a", text: "Retry")

    expect(Fwup, :create_firmware_delta_file, fn _, _ ->
      {:ok,
       %{
         tool: "fwup",
         size: "1000",
         source_size: "2000",
         target_size: "3000",
         filepath: tmp_dir,
         tool_metadata: %{}
       }}
    end)

    expect(File, :upload_file, fn _, _ -> :ok end)

    :ok = Firmwares.generate_firmware_delta(delta, source_firmware, deployment_group.firmware)

    conn
    |> assert_has("div", text: "Ready", timeout: 100)
    |> assert_has("a", text: "Delete")
    |> refute_has("a", text: "Retry")
  end

  test "delete delta", %{
    conn: conn,
    source_firmware: source_firmware,
    target_firmware: target_firmware
  } do
    {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)
    {:ok, delta} = Firmwares.fail_firmware_delta(delta)

    expect(Oban, :insert, fn _ -> {:ok, %Oban.Job{}} end)

    conn
    |> assert_has("a", text: "Delete", timeout: 100)
    |> click_link("Delete")
    |> refute_has("div", text: "Failed", timeout: 100)

    refute Repo.reload(delta)
  end

  test "retry delta", %{
    conn: conn,
    source_firmware: %{id: source_id} = source_firmware,
    target_firmware: %{id: target_id} = target_firmware
  } do
    {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)
    {:ok, delta} = Firmwares.fail_firmware_delta(delta)

    expect(Firmwares, :attempt_firmware_delta, fn ^source_id, ^target_id ->
      {:ok, :started}
    end)

    expect(Oban, :insert, fn _ -> {:ok, %Oban.Job{}} end)

    conn
    |> assert_has("a", text: "Retry", timeout: 100)
    |> click_link("Retry")

    refute Repo.reload(delta)
  end

  test "devices counter is a link to devices list page", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> assert_has(
      "a[href='/org/#{org.name}/#{product.name}/devices?deployment_id=#{deployment_group.id}']",
      text: "Devices"
    )
  end

  test "shows the deployment group", %{
    conn: conn,
    deployment_group: deployment_group
  } do
    conn
    |> assert_has("svg[data-is-active=true]")
    |> assert_has("span", text: "0")
    |> then(fn conn ->
      for tag <- deployment_group.conditions.tags do
        assert_has(conn, "span", text: tag)
      end

      conn
    end)
  end

  test "shows the deployment group with device count", %{
    conn: conn,
    org: org,
    product: product,
    fixture: %{firmware: firmware},
    deployment_group: deployment_group,
    device: device
  } do
    Devices.update_deployment_group(device, deployment_group)

    # deleted devices shouldn't be included in the count
    Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})
    |> Devices.update_deployment_group(deployment_group)

    assert_has(conn, "span", text: "1")
  end

  test "you can toggle the deployment group being on or off", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> click_button("Pause")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment_group} =
        ManagedDeployments.get_deployment_group(deployment_group.id)

      refute reloaded_deployment_group.is_active
      assert_has(conn, "button", text: "Resume")

      logs = AuditLogs.logs_for(deployment_group)
      assert Enum.count(logs) == 2
      assert List.first(logs).description =~ ~r/marked deployment/

      conn
    end)
    |> click_button("Resume")
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> then(fn conn ->
      {:ok, reloaded_deployment_group} =
        ManagedDeployments.get_deployment_group(deployment_group.id)

      assert reloaded_deployment_group.is_active
      assert_has(conn, "button", text: "Pause")

      logs = AuditLogs.logs_for(reloaded_deployment_group)
      assert Enum.count(logs) == 3
      assert List.first(logs).description =~ ~r/marked deployment/

      conn
    end)
  end

  test "displays text when every device in deployment group matches conditions", %{
    conn: conn,
    org: org,
    product: product,
    fixture: %{firmware: firmware},
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{
      deployment_id: deployment_group.id,
      tags: ["beta"]
    })

    Fixtures.device_fixture(org, product, firmware, %{
      deployment_id: deployment_group.id,
      tags: ["beta-edge"]
    })

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "100% of devices in this deployment group match conditions")
  end

  test "removing device from deployment that doesn't match conditions", %{
    conn: conn,
    org: org,
    product: product,
    fixture: %{firmware: firmware},
    deployment_group: deployment_group
  } do
    device1 =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        tags: ["foo"]
      })

    conn
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
    org: org,
    product: product,
    fixture: %{firmware: firmware}
  } do
    device1 =
      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["beta"]
      })

    conn
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
