defmodule NervesHub.Devices.FlappingConnectionsTest do
  # Not async: these tests read/write the AnalyticsRepo (ClickHouse).
  use NervesHub.DataCase, async: false

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")

    {:ok, %{user: user, org: org, product: product, firmware: firmware, device: device}}
  end

  # Inserts `count` connection-history rows for `device`, each established
  # `minutes_ago` minutes in the past (defaults to within the flapping window).
  #
  # Each row gets a distinct `established_at` (a second apart): the underlying
  # ReplacingMergeTree dedupes on (org_id, product_id, device_id, established_at),
  # so reusing a timestamp would collapse the rows into one when queried FINAL.
  defp insert_connections(device, count, minutes_ago \\ 5) do
    base = DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)

    for offset <- 1..count do
      established_at = DateTime.add(base, -offset, :second)

      connection = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: established_at,
        last_seen_at: DateTime.utc_now(),
        disconnected_at: DateTime.utc_now()
      }

      {:ok, _} =
        connection
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()
    end

    :ok
  end

  describe "flapping_connections/1" do
    test "returns devices that reconnected more than 10 times in the last hour", %{
      product: product,
      device: device
    } do
      insert_connections(device, 11)

      assert [{flapping_device, count}] = Connections.flapping_connections(product)
      assert flapping_device.id == device.id
      assert count == 11
    end

    test "excludes devices at or below the flapping threshold of 10", %{
      product: product,
      device: device
    } do
      insert_connections(device, 10)

      assert Connections.flapping_connections(product) == []
    end

    test "ignores connections established more than an hour ago", %{
      product: product,
      device: device
    } do
      # plenty of reconnections, but all outside the one hour window
      insert_connections(device, 20, 90)

      assert Connections.flapping_connections(product) == []
    end

    test "only counts connections within the window when a device has both recent and old", %{
      product: product,
      device: device
    } do
      insert_connections(device, 5, 90)
      insert_connections(device, 11, 5)

      assert [{_device, count}] = Connections.flapping_connections(product)
      assert count == 11
    end

    test "only includes devices belonging to the given product", %{
      user: user,
      org: org,
      product: product,
      device: device,
      tmp_dir: tmp_dir
    } do
      other_product = Fixtures.product_fixture(user, org, %{name: "Other Product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(org_key, other_product, %{dir: tmp_dir})
      other_device = Fixtures.device_fixture(org, other_product, other_firmware)

      insert_connections(device, 11)
      insert_connections(other_device, 15)

      assert [{flapping_device, _count}] = Connections.flapping_connections(product)
      assert flapping_device.id == device.id
    end

    test "returns multiple flapping devices ordered by connection count descending", %{
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      noisier_device = Fixtures.device_fixture(org, product, firmware)

      insert_connections(device, 12)
      insert_connections(noisier_device, 30)

      assert [{first, first_count}, {second, second_count}] =
               Connections.flapping_connections(product)

      assert first.id == noisier_device.id
      assert first_count == 30
      assert second.id == device.id
      assert second_count == 12
    end

    test "returns an empty list when there is no connection history", %{product: product} do
      assert Connections.flapping_connections(product) == []
    end
  end
end
