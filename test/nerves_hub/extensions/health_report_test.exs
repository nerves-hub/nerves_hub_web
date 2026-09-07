defmodule NervesHub.Extensions.HealthReportTest do
  @moduledoc """
  What a health report leaves behind, now that the report payload is not stored
  as one blob: a status row, alarm rows, and metadata merged onto the
  connection.
  """

  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)
    connection = Fixtures.device_connection_fixture(device)

    state =
      State.new(%DeviceInfo{
        device_id: device.id,
        product_id: product.id,
        org_id: org.id,
        connection_ref: connection.id
      })

    %{device: device, product: product, connection: connection, state: state}
  end

  defp report(state, value) do
    {_state, []} = Health.handle_in("report", %{"value" => value}, state)
    :ok
  end

  test "stores the status, the alarms and the metadata", %{device: device, state: state} do
    :ok =
      report(state, %{
        "metrics" => %{"cpu_usage_percent" => 12.0},
        "alarms" => %{"Elixir.MyApp.HighTemp" => "too hot"},
        "metadata" => %{"serial_number" => "SN-1234"}
      })

    assert %{status: :healthy} = Repo.get_by!(DeviceHealth, device_id: device.id)
    assert Alarms.current_alarms_for_device(device) == [{"MyApp.HighTemp", "too hot"}]
    assert %{metadata: %{"serial_number" => "SN-1234"}} = Connections.get_latest_for_device(device.id)
  end

  test "a second report replaces the status row rather than appending", %{device: device, state: state} do
    :ok = report(state, %{"metrics" => %{"cpu_usage_percent" => 12.0}})
    :ok = report(state, %{"metrics" => %{"cpu_usage_percent" => 99.0}})

    assert Repo.aggregate(where(DeviceHealth, device_id: ^device.id), :count) == 1
    assert %{status: :unhealthy} = Repo.get_by!(DeviceHealth, device_id: device.id)
  end

  test "an alarm that clears is removed on the next report", %{device: device, state: state} do
    :ok = report(state, %{"alarms" => %{"HighTemp" => "too hot"}})
    assert Alarms.current_alarms_for_device(device) == [{"HighTemp", "too hot"}]

    :ok = report(state, %{"alarms" => %{}})
    assert Alarms.current_alarms_for_device(device) == nil
  end

  test "metadata merges rather than replacing", %{device: device, state: state} do
    :ok = report(state, %{"metadata" => %{"serial_number" => "SN-1234"}})
    :ok = report(state, %{"metadata" => %{"firmware" => "1.2.3"}})

    assert %{metadata: %{"serial_number" => "SN-1234", "firmware" => "1.2.3"}} =
             Connections.get_latest_for_device(device.id)
  end

  test "a report carrying neither alarms nor metadata still records status", %{device: device, state: state} do
    :ok = report(state, %{"metrics" => %{"cpu_usage_percent" => 12.0}})

    assert %{status: :healthy} = Repo.get_by!(DeviceHealth, device_id: device.id)
    assert Alarms.current_alarms_for_device(device) == nil
    assert %{metadata: %{}} = Connections.get_latest_for_device(device.id)
  end
end
