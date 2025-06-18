defmodule NervesHub.Workers.RemoveDeviceFromPenaltyBoxTest do
  use NervesHub.DataCase

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Workers.RemoveDeviceFromPenaltyBox

  test "clears expected device columns" do
    %{device: device} = Fixtures.standard_fixture()

    {:ok, device} =
      Devices.update_device(device, %{
        updates_blocked_until: DateTime.utc_now(),
        update_attempts: [DateTime.utc_now(), DateTime.utc_now()]
      })

    assert device.updates_blocked_until
    assert length(device.update_attempts) == 2

    assert {:ok, device} = perform_job(RemoveDeviceFromPenaltyBox, %{"device_id" => device.id})

    refute device.updates_blocked_until
    assert device.update_attempts == []
  end

  test "doesn't blow up if device doesn't exist" do
    assert :ok = perform_job(RemoveDeviceFromPenaltyBox, %{"device_id" => 123})
  end
end
