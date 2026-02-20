defmodule NervesHubWeb.Live.DeploymentGroups.Tabs.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  test "updates the available firmware list when new firmware is uploaded", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("div", text: "Release settings")
      |> assert_has("option[value=\"#{firmware.id}\"]", text: "#{firmware.version}")

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> assert_has("option[value=\"#{new_firmware.id}\"]", text: "#{new_firmware.version}", timeout: 100)
    |> assert_has("p",
      text: "New firmware #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)}) is available for selection"
    )
  end

  test "updates the available firmware list when a firmware is deleted", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware_1 = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    firmware_2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware_1)

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("div", text: "Release settings")
      |> assert_has("option[value=\"#{firmware_1.id}\"]", text: "#{firmware_1.version}")
      |> assert_has("option[value=\"#{firmware_2.id}\"]", text: "#{firmware_2.version}")

    Firmwares.delete_firmware(firmware_2)

    conn
    |> assert_has("option[value=\"#{firmware_1.id}\"]", text: "#{firmware_1.version}", timeout: 100)
    |> refute_has("option[value=\"#{firmware_2.id}\"]", text: "#{firmware_2.version}")
    |> assert_has("p",
      text:
        "Firmware list has been updated. Firmware #{firmware_2.version} (#{String.slice(firmware_2.uuid, 0..7)}) has been deleted by another user."
    )
  end
end
