defmodule NervesHubWeb.Live.DeploymentGroups.Show.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  setup context do
    %{
      org: org,
      product: product,
      deployment_group: deployment_group
    } = context

    conn =
      context.conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("div", text: "Release History")

    %{context | conn: conn}
  end

  test "successfully creates a new release", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> refute_has("div", text: "Show notes")
    |> assert_has("div", text: "Firmware: #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)})")
    |> assert_has("div", text: "Release settings updated")
  end

  test "successfully creates a new release with a description and notes", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> fill_in("Description", with: "Snoot boops")
    |> fill_in("Notes", with: "All the snoots need some boops")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("div", text: "Snoot boops")
    |> assert_has("div", text: "Show notes")
    |> assert_has("div", text: "All the snoots need some boops")
    |> assert_has("div", text: "Firmware: #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)})")
    |> assert_has("div", text: "Release settings updated")
  end

  test "release description can't be longer than 100 characters", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> fill_in("Description", with: Enum.map_join(1..10, " ", fn _ -> "Snoot boops" end))
    |> fill_in("Notes", with: "All the snoots need some boops")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("div", text: "An error occurred while updating the release settings")
  end

  test "updates the available firmware list when new firmware is uploaded", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

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
    deployment_group = Fixtures.deployment_group_fixture(firmware_1, %{user: user})

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

  test "shows created releases", %{conn: conn} do
    assert_has(conn, "div", text: "Firmware: 1.0.0")
  end
end
