defmodule NervesHub.Devices.AlarmsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.DeviceAlarm
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    info = %DeviceInfo{device_id: device.id, product_id: product.id, org_id: org.id}

    %{org: org, product: product, firmware: firmware, device: device, info: info}
  end

  defp stored(device) do
    DeviceAlarm
    |> where(device_id: ^device.id)
    |> order_by([a], asc: a.alarm)
    |> Repo.all()
  end

  describe "sync/3" do
    test "raises the alarms a report carries", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => "too hot", "LowDisk" => "nearly full"})

      assert [%{alarm: "HighTemp", description: "too hot"}, %{alarm: "LowDisk"}] = stored(device)
    end

    test "keeps raised_at across re-reports of the same alarm", %{device: device, info: info} do
      earlier = DateTime.add(DateTime.utc_now(), -30, :minute)

      :ok = Alarms.sync(info, %{"HighTemp" => "too hot"}, earlier)
      [%{raised_at: raised_at}] = stored(device)

      # The device re-asserts its whole alarm set on every report; the episode
      # started when it was first seen, not when it was last mentioned.
      :ok = Alarms.sync(info, %{"HighTemp" => "still too hot"}, DateTime.utc_now())

      assert [%{raised_at: ^raised_at, description: "still too hot"}] = stored(device)
    end

    test "resolves an alarm the report no longer carries", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => "too hot", "LowDisk" => "nearly full"})
      :ok = Alarms.sync(info, %{"LowDisk" => "nearly full"})

      assert [%{alarm: "LowDisk"}] = stored(device)
    end

    test "an empty report resolves everything", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => "too hot"})
      :ok = Alarms.sync(info, %{})

      assert stored(device) == []
    end

    test "strips the Elixir. prefix the alarm handler carries", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"Elixir.MyApp.HighTemp" => "too hot"})

      assert [%{alarm: "MyApp.HighTemp"}] = stored(device)
    end

    test "ignores entries that are not usable alarms", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"Elixir." => "empty once stripped", "Real" => "kept"})

      assert [%{alarm: "Real"}] = stored(device)
    end

    test "coerces a non-string description", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => %{"celsius" => 91}})

      assert [%{description: description}] = stored(device)
      assert description =~ "celsius"
    end

    test "a non-map payload leaves the device alone", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => "too hot"})
      :ok = Alarms.sync(info, "not a map")

      assert [%{alarm: "HighTemp"}] = stored(device)
    end

    test "one device's alarms do not touch another's", %{org: org, product: product, firmware: firmware, info: info} do
      other = Fixtures.device_fixture(org, product, firmware)
      other_info = %DeviceInfo{device_id: other.id, product_id: product.id, org_id: org.id}

      :ok = Alarms.sync(info, %{"HighTemp" => "too hot"})
      :ok = Alarms.sync(other_info, %{"LowDisk" => "nearly full"})
      :ok = Alarms.sync(other_info, %{})

      assert [%{alarm: "HighTemp"}] = stored(%{id: info.device_id})
      assert stored(other) == []
    end
  end

  describe "reads" do
    test "current_alarms_for_device/1 returns nil when there are none", %{device: device} do
      assert Alarms.current_alarms_for_device(device) == nil
    end

    test "current_alarms_for_device/1 returns name and description", %{device: device, info: info} do
      :ok = Alarms.sync(info, %{"HighTemp" => "too hot"})

      assert Alarms.current_alarms_for_device(device) == [{"HighTemp", "too hot"}]
    end

    test "get_current_alarm_types/1 is the product's distinct raised alarms", %{
      org: org,
      product: product,
      firmware: firmware,
      info: info
    } do
      other = Fixtures.device_fixture(org, product, firmware)
      other_info = %DeviceInfo{device_id: other.id, product_id: product.id, org_id: org.id}

      :ok = Alarms.sync(info, %{"HighTemp" => "too hot", "LowDisk" => "nearly full"})
      :ok = Alarms.sync(other_info, %{"HighTemp" => "too hot"})

      assert Alarms.get_current_alarm_types(product.id) == ["HighTemp", "LowDisk"]
    end

    test "current_alarms_count/1 counts devices, not alarms", %{
      org: org,
      product: product,
      firmware: firmware,
      info: info
    } do
      other = Fixtures.device_fixture(org, product, firmware)
      other_info = %DeviceInfo{device_id: other.id, product_id: product.id, org_id: org.id}

      :ok = Alarms.sync(info, %{"HighTemp" => "too hot", "LowDisk" => "nearly full"})
      :ok = Alarms.sync(other_info, %{"HighTemp" => "too hot"})

      assert Alarms.current_alarms_count(product.id) == 2

      :ok = Alarms.sync(other_info, %{})

      assert Alarms.current_alarms_count(product.id) == 1
    end
  end
end
