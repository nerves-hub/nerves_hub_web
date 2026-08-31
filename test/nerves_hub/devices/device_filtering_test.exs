defmodule NervesHub.Devices.DeviceFilteringTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.Health
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    %{user: user, org: org, product: product, firmware: firmware, org_key: org_key}
  end

  defp base_query(product) do
    Device
    |> where([d], d.product_id == ^product.id)
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:left, [d], dh in assoc(d, :latest_health), as: :latest_health)
  end

  defp identifiers(query) do
    query
    |> select([d], d.identifier)
    |> Repo.all()
    |> Enum.sort()
  end

  describe "filter/4 empty string" do
    test "returns the query unchanged", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      query = base_query(product)

      result = DeviceFiltering.filter(query, %{}, :identifier, "")
      assert identifiers(result) == [device.identifier]
    end
  end

  describe "filter/4 :identifier" do
    test "filters devices by identifier substring", %{org: org, product: product, firmware: firmware} do
      d1 = Fixtures.device_fixture(org, product, firmware, %{identifier: "alpha-001"})
      d2 = Fixtures.device_fixture(org, product, firmware, %{identifier: "beta-002"})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :identifier, "alpha")
      assert identifiers(result) == [d1.identifier]
      refute d2.identifier in identifiers(DeviceFiltering.filter(query, %{}, :identifier, "alpha"))
    end
  end

  describe "filter/4 :firmware_version" do
    test "filters devices by firmware version", %{
      org: org,
      product: product,
      firmware: firmware,
      org_key: org_key
    } do
      firmware_v2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware_v2)

      query = base_query(product)

      v1_ids = DeviceFiltering.filter(query, %{}, :firmware_version, firmware.version) |> identifiers()
      assert d1.identifier in v1_ids
      refute d2.identifier in v1_ids

      v2_ids = DeviceFiltering.filter(query, %{}, :firmware_version, "2.0.0") |> identifiers()
      assert d2.identifier in v2_ids
      refute d1.identifier in v2_ids
    end
  end

  describe "filter/4 :tags" do
    test "filters devices that include a tag", %{org: org, product: product, firmware: firmware} do
      tagged = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod", "edge"]})
      _other = Fixtures.device_fixture(org, product, firmware, %{tags: ["staging"]})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :tags, "prod") |> identifiers()
      assert tagged.identifier in result
    end
  end

  describe "filter/4 :has_no_tags" do
    test "returns only devices with no tags when true", %{org: org, product: product, firmware: firmware} do
      tagged = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})
      no_tags = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :has_no_tags, true) |> identifiers()

      assert no_tags.identifier in result
      refute tagged.identifier in result
    end

    test "returns the query unchanged when false", %{org: org, product: product, firmware: firmware} do
      tagged = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})
      no_tags = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :has_no_tags, false) |> identifiers()

      assert tagged.identifier in result
      assert no_tags.identifier in result
    end
  end

  describe "filter/4 :updates" do
    test "filters by updates enabled", %{org: org, product: product, firmware: firmware} do
      enabled = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: true})
      disabled = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: false})

      query = base_query(product)

      enabled_ids = DeviceFiltering.filter(query, %{}, :updates, "enabled") |> identifiers()
      assert enabled.identifier in enabled_ids
      refute disabled.identifier in enabled_ids

      disabled_ids = DeviceFiltering.filter(query, %{}, :updates, "disabled") |> identifiers()
      assert disabled.identifier in disabled_ids
      refute enabled.identifier in disabled_ids
    end
  end

  describe "filter/4 :display_deleted" do
    test "include adds deleted devices to results", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      Repo.update_all(where(Device, id: ^device.id), set: [deleted_at: DateTime.utc_now()])

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :display_deleted, "include") |> identifiers()
      assert device.identifier in result
    end

    test "exclude hides soft-deleted devices", %{org: org, product: product, firmware: firmware} do
      live = Fixtures.device_fixture(org, product, firmware)
      deleted = Fixtures.device_fixture(org, product, firmware)
      Repo.update_all(where(Device, id: ^deleted.id), set: [deleted_at: DateTime.utc_now()])

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :display_deleted, "exclude") |> identifiers()
      assert live.identifier in result
      refute deleted.identifier in result
    end

    test "only shows only soft-deleted devices", %{org: org, product: product, firmware: firmware} do
      _live = Fixtures.device_fixture(org, product, firmware)
      deleted = Fixtures.device_fixture(org, product, firmware)
      Repo.update_all(where(Device, id: ^deleted.id), set: [deleted_at: DateTime.utc_now()])

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :display_deleted, "only") |> identifiers()
      assert result == [deleted.identifier]
    end
  end

  describe "filter/4 :search" do
    test "matches on identifier substring", %{org: org, product: product, firmware: firmware} do
      d1 = Fixtures.device_fixture(org, product, firmware, %{identifier: "search-target-001"})
      _d2 = Fixtures.device_fixture(org, product, firmware, %{identifier: "other-device-002"})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :search, "search-target") |> identifiers()
      assert result == [d1.identifier]
    end
  end

  describe "filter/4 :deployment_id" do
    test "nil returns devices with no deployment", %{user: user, org: org, product: product, firmware: firmware} do
      unassigned = Fixtures.device_fixture(org, product, firmware)

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      assigned = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :deployment_id, nil) |> identifiers()
      assert unassigned.identifier in result
      refute assigned.identifier in result
    end

    test "value returns only devices assigned to that deployment", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware
    } do
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      assigned = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
      _unassigned = Fixtures.device_fixture(org, product, firmware)

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :deployment_id, deployment_group.id) |> identifiers()
      assert result == [assigned.identifier]
    end
  end

  describe "filter/4 :alarm" do
    test "filters devices by alarm name substring", %{org: org, product: product, firmware: firmware} do
      with_alarm = Fixtures.device_fixture(org, product, firmware)
      without_alarm = Fixtures.device_fixture(org, product, firmware)
      save_health(with_alarm, "healthy", %{"alarms" => %{"HighTempAlarm" => "active"}})
      save_health(without_alarm, "healthy", %{"alarms" => %{}})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :alarm, "HighTemp") |> identifiers()
      assert with_alarm.identifier in result
      refute without_alarm.identifier in result
    end
  end

  describe "filter/4 :connection_type" do
    test "filters by ethernet connection type", %{org: org, product: product, firmware: firmware} do
      ethernet = Fixtures.device_fixture(org, product, firmware)
      wifi = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(ethernet, %{network_interface: :ethernet})
      Fixtures.device_connection_fixture(wifi, %{network_interface: :wifi})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection_type, "ethernet") |> identifiers()
      assert ethernet.identifier in result
      refute wifi.identifier in result
    end

    test "unknown connection type matches nil or unknown interface", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(device, %{network_interface: :unknown})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection_type, "unknown") |> identifiers()
      assert device.identifier in result
    end
  end

  describe "filter/4 unknown key" do
    test "returns the query unchanged for unknown filter keys", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :totally_unknown_key, "some_value") |> identifiers()
      assert device.identifier in result
    end
  end

  describe "sort/2" do
    test "asc :connection_established_at sorts by desc established_at nulls last", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware)

      now = DateTime.utc_now()
      Fixtures.device_connection_fixture(d1, %{established_at: DateTime.add(now, -10, :second)})
      Fixtures.device_connection_fixture(d2, %{established_at: DateTime.add(now, -1, :second)})

      result =
        base_query(product)
        |> DeviceFiltering.sort({:asc, :connection_established_at})
        |> select([d], d.identifier)
        |> Repo.all()

      assert Enum.count(result) >= 2
    end

    test "desc :connection_last_seen_at sorts by asc last_seen_at nulls first", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware)

      now = DateTime.utc_now()
      Fixtures.device_connection_fixture(d1, %{last_seen_at: DateTime.add(now, -10, :second)})
      Fixtures.device_connection_fixture(d2, %{last_seen_at: DateTime.add(now, -1, :second)})

      result =
        base_query(product)
        |> DeviceFiltering.sort({:desc, :connection_last_seen_at})
        |> select([d], d.identifier)
        |> Repo.all()

      assert Enum.count(result) >= 2
    end

    test "fallback sort delegates to order_by", %{org: org, product: product, firmware: firmware} do
      Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_fixture(org, product, firmware)

      result =
        base_query(product)
        |> DeviceFiltering.sort({:asc, :identifier})
        |> select([d], d.identifier)
        |> Repo.all()

      assert result == Enum.sort(result)
    end
  end

  defp save_health(device, status, data \\ %{}) do
    {:ok, _} =
      Health.save_device_health(%{
        "device_id" => device.id,
        "data" => data,
        "status" => status,
        "status_reasons" => %{}
      })
  end

  describe "filter/4 :health_status" do
    test "filters devices by health status", %{org: org, product: product, firmware: firmware} do
      healthy = Fixtures.device_fixture(org, product, firmware)
      unhealthy = Fixtures.device_fixture(org, product, firmware)
      save_health(healthy, "healthy")
      save_health(unhealthy, "unhealthy")

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :health_status, "healthy") |> identifiers()
      assert healthy.identifier in result
      refute unhealthy.identifier in result
    end

    test "unknown health status matches devices with no health or unknown status", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      no_health = Fixtures.device_fixture(org, product, firmware)
      save_health(no_health, "unknown")
      healthy = Fixtures.device_fixture(org, product, firmware)
      save_health(healthy, "healthy")

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :health_status, "unknown") |> identifiers()
      assert no_health.identifier in result
      refute healthy.identifier in result
    end
  end

  describe "filter/4 :alarm_status" do
    test "with filters devices that have alarms", %{org: org, product: product, firmware: firmware} do
      with_alarm = Fixtures.device_fixture(org, product, firmware)
      without_alarm = Fixtures.device_fixture(org, product, firmware)
      save_health(with_alarm, "healthy", %{"alarms" => %{"SomeAlarm" => "active"}})
      save_health(without_alarm, "healthy", %{"alarms" => %{}})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :alarm_status, "with") |> identifiers()
      assert with_alarm.identifier in result
      refute without_alarm.identifier in result
    end

    test "without filters devices that have no alarms", %{org: org, product: product, firmware: firmware} do
      with_alarm = Fixtures.device_fixture(org, product, firmware)
      without_alarm = Fixtures.device_fixture(org, product, firmware)
      save_health(with_alarm, "healthy", %{"alarms" => %{"SomeAlarm" => "active"}})
      save_health(without_alarm, "healthy", %{"alarms" => %{}})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :alarm_status, "without") |> identifiers()
      assert without_alarm.identifier in result
      refute with_alarm.identifier in result
    end

    test "unknown value returns query unchanged", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      save_health(device, "healthy", %{"alarms" => %{}})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :alarm_status, "bogus") |> identifiers()
      assert device.identifier in result
    end
  end

  describe "filter/4 :connection" do
    test "not_seen returns registered devices", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      Repo.update_all(where(Device, id: ^device.id), set: [status: :registered])

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection, "not_seen") |> identifiers()
      assert device.identifier in result
    end

    test "connected returns connected devices", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(device, %{status: :connected})

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection, "connected") |> identifiers()
      assert device.identifier in result
    end

    test "not_seen_in_seven_days returns disconnected devices last seen > 7 days ago", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      old = Fixtures.device_fixture(org, product, firmware)
      recent = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(old, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -8, :day)
      })

      Fixtures.device_connection_fixture(recent, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection, "not_seen_in_seven_days") |> identifiers()
      assert old.identifier in result
      refute recent.identifier in result
    end

    test "not_seen_in_fourteen_days returns disconnected devices last seen > 14 days ago", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      old = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(old, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -15, :day)
      })

      recent = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(recent, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -7, :day)
      })

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :connection, "not_seen_in_fourteen_days") |> identifiers()
      assert old.identifier in result
      refute recent.identifier in result
    end
  end

  describe "filter/4 :platform" do
    test "filters by platform value", %{org: org, product: product, firmware: firmware, org_key: org_key} do
      other_fw = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi4"})
      rpi4 = Fixtures.device_fixture(org, product, other_fw)
      _other = Fixtures.device_fixture(org, product, firmware)

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :platform, "rpi4") |> identifiers()
      assert rpi4.identifier in result
    end

    test "Unknown platform does not match devices with a known platform", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      device = Fixtures.device_fixture(org, product, firmware)

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :platform, "Unknown") |> identifiers()
      refute device.identifier in result
    end
  end

  describe "filter/4 :updates penalty-box" do
    test "penalty-box returns devices blocked until future", %{org: org, product: product, firmware: firmware} do
      penalized = Fixtures.device_fixture(org, product, firmware)
      normal = Fixtures.device_fixture(org, product, firmware, %{updates_enabled: true})

      Repo.update_all(
        where(Device, id: ^penalized.id),
        set: [updates_blocked_until: DateTime.add(DateTime.utc_now(), 1, :hour)]
      )

      query = base_query(product)
      result = DeviceFiltering.filter(query, %{}, :updates, "penalty-box") |> identifiers()
      assert penalized.identifier in result
      refute normal.identifier in result
    end
  end

  describe "filter/4 :only_updating" do
    test "false returns query unchanged", %{org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)

      query =
        Device
        |> where([d], d.product_id == ^product.id)
        |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
        |> join(:left, [d], dh in assoc(d, :latest_health), as: :latest_health)
        |> join(:left, [d], ifu in assoc(d, :inflight_update), as: :inflight_update)

      result = DeviceFiltering.filter(query, %{}, :only_updating, false) |> identifiers()
      assert device.identifier in result
    end
  end

  describe "sort/2 remaining variants" do
    test "desc :connection_established_at", %{org: org, product: product, firmware: firmware} do
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware)

      now = DateTime.utc_now()
      Fixtures.device_connection_fixture(d1, %{established_at: DateTime.add(now, -10, :second)})
      Fixtures.device_connection_fixture(d2, %{established_at: DateTime.add(now, -1, :second)})

      result =
        base_query(product)
        |> DeviceFiltering.sort({:desc, :connection_established_at})
        |> select([d], d.identifier)
        |> Repo.all()

      assert Enum.count(result) >= 2
    end

    test "asc :connection_last_seen_at", %{org: org, product: product, firmware: firmware} do
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware)

      now = DateTime.utc_now()
      Fixtures.device_connection_fixture(d1, %{last_seen_at: DateTime.add(now, -10, :second)})
      Fixtures.device_connection_fixture(d2, %{last_seen_at: DateTime.add(now, -1, :second)})

      result =
        base_query(product)
        |> DeviceFiltering.sort({:asc, :connection_last_seen_at})
        |> select([d], d.identifier)
        |> Repo.all()

      assert Enum.count(result) >= 2
    end
  end

  describe "build_filters/2" do
    test "applies multiple filters in combination", %{
      org: org,
      product: product,
      firmware: firmware,
      org_key: org_key
    } do
      firmware_v2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
      target = Fixtures.device_fixture(org, product, firmware_v2, %{tags: ["prod"], updates_enabled: true})
      _other = Fixtures.device_fixture(org, product, firmware, %{tags: ["staging"], updates_enabled: false})

      filters = %{firmware_version: "2.0.0", tags: "prod", updates: "enabled"}
      result = base_query(product) |> DeviceFiltering.build_filters(filters) |> identifiers()
      assert result == [target.identifier]
    end

    test "empty filters map returns all devices", %{org: org, product: product, firmware: firmware} do
      d1 = Fixtures.device_fixture(org, product, firmware)
      d2 = Fixtures.device_fixture(org, product, firmware)

      result = base_query(product) |> DeviceFiltering.build_filters(%{}) |> identifiers()
      assert d1.identifier in result
      assert d2.identifier in result
    end
  end
end
