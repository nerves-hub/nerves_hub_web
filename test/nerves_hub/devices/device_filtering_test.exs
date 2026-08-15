defmodule NervesHub.Devices.DeviceFilteringTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFiltering
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
