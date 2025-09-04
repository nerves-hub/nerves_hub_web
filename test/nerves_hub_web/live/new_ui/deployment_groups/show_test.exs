defmodule NervesHubWeb.Live.NewUI.DeploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  setup context do
    %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      fixture: %{firmware: source_firmware},
      tmp_dir: tmp_dir
    } = context

    target_firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(org, target_firmware, %{
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
      |> init_test_session(%{"new_ui" => true})
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    [
      conn: conn,
      device: device,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      source_firmware_metadata: source_firmware_metadata
    ]
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
    target_firmware: target_firmware,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    :ok = UpdateStats.log_update(device, source_firmware_metadata)

    other_firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "2.0.1", dir: tmp_dir})

    {:ok, other_firmware_metadata} = Firmwares.metadata_from_firmware(other_firmware)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{
        firmware_id: other_firmware.id
      })

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
    |> assert_has("option[selected]", text: target_firmware.version)
    |> select("Version", option: "2.0.1")
    |> assert_has("span", text: "Update count:")
    |> assert_has("span", text: "2")
  end
end
