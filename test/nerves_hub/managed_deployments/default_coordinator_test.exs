defmodule NervesHub.ManagedDeployments.DefaultCoordinatorTest do
  use NervesHub.DataCase, async: false

  import ExUnit.CaptureLog

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.Orchestrator.DefaultCoordinator

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})

    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    {:ok, device} =
      Devices.update_firmware_metadata(
        device,
        %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
        :validated,
        false
      )

    device = Deployments.update_deployment_group(device, deployment_group)

    {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
    :ok = Connections.device_connected(connection.id)

    %{deployment_group: deployment_group, device: device}
  end

  test "a device penalty boxed for its failures gets a full set of tries once the penalty ends", %{
    deployment_group: deployment_group,
    device: device
  } do
    now = DateTime.utc_now(:second)
    {:ok, device} = Devices.update_device(device, %{update_attempts: [now, now, now]})

    # Skipping a device asks for another pass, to find someone else for the slot
    assert DefaultCoordinator.schedule_updates(deployment_group)

    device = Repo.reload(device)
    assert Updates.device_in_penalty_box?(device)
    assert device.update_attempts == []
    refute inflight_update?(device)

    {:ok, _device} = Devices.update_device(device, %{updates_blocked_until: DateTime.add(now, -1, :second)})

    refute DefaultCoordinator.schedule_updates(deployment_group)
    assert inflight_update?(device)
  end

  test "penalty boxes a device that has no firmware on record", %{deployment_group: deployment_group, device: device} do
    now = DateTime.utc_now(:second)

    device
    |> change(current_device_firmware_id: nil, update_attempts: [now, now, now])
    |> Repo.update!()

    # config/test.exs pins the logger to :warning, and the penalty is logged at :info
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log(fn -> assert DefaultCoordinator.schedule_updates(deployment_group) end)

    assert log =~ "put in penalty box"
    assert Updates.device_in_penalty_box?(Repo.reload(device))
  end

  defp inflight_update?(device), do: Repo.exists?(where(InflightUpdate, device_id: ^device.id))
end
