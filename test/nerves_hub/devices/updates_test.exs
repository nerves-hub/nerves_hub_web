defmodule NervesHub.Devices.UpdatesTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})
    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    # Update firmware UUID so device isn't "up to date" by default
    {:ok, device} = set_different_firmware_uuid(device)

    %{user: user, device: device, deployment_group: deployment_group}
  end

  describe "verify_update_eligibility/3" do
    test "returns error when deployment group is not active", %{device: device, deployment_group: deployment_group} do
      inactive_group = %{deployment_group | is_active: false}

      assert {:error, :deployment_group_not_active, ^device} =
               Updates.verify_update_eligibility(device, inactive_group)
    end

    test "returns error and clears inflight update when updates_enabled is false", %{
      device: device,
      deployment_group: deployment_group
    } do
      device = %{device | updates_enabled: false}

      assert {:error, :updates_blocked, ^device} =
               Updates.verify_update_eligibility(device, deployment_group)
    end
  end

  describe "device_in_penalty_box?/2" do
    test "returns false for DeviceInfo with nil updates_blocked_until" do
      device_info = %DeviceInfo{device_updates_blocked_until: nil}
      refute Updates.device_in_penalty_box?(device_info)
    end

    test "returns true for DeviceInfo with future updates_blocked_until" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      device_info = %DeviceInfo{device_updates_blocked_until: future}
      assert Updates.device_in_penalty_box?(device_info)
    end

    test "returns false for DeviceInfo with past updates_blocked_until" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      device_info = %DeviceInfo{device_updates_blocked_until: past}
      refute Updates.device_in_penalty_box?(device_info)
    end

    test "returns false for Device with nil updates_blocked_until", %{device: device} do
      refute Updates.device_in_penalty_box?(device)
    end
  end

  describe "available_for_priority_update/2" do
    test "returns empty list when priority_queue_firmware_version_threshold is nil", %{
      deployment_group: deployment_group
    } do
      group_without_threshold = %{deployment_group | priority_queue_firmware_version_threshold: nil}
      result = Updates.available_for_priority_update(group_without_threshold, 10)
      assert result == []
    end
  end

  describe "firmware_validated/1" do
    test "updates device firmware_validation_status and broadcasts", %{device: device} do
      device_info = to_device_info(device)

      PubSub.subscribe(device.id)

      :ok = Updates.firmware_validated(device_info)

      assert_receive %Broadcast{event: "firmware:validated"}, 500

      device = Repo.reload(device)
      assert device.firmware_validation_status == :validated
    end

    test "updates DeviceFirmware record's validation status", %{device: device} do
      device_info = to_device_info(device)

      :ok = Updates.firmware_validated(device_info)

      device = Repo.preload(Repo.reload(device), :current_device_firmware)

      if df = device.current_device_firmware do
        assert df.firmware_validation_status == :validated
      end
    end
  end

  describe "enable_updates/2" do
    test "enables updates and clears update attempts", %{device: device, user: user} do
      {:ok, device} = Devices.update_device(device, %{updates_enabled: false, update_attempts: []})

      {:ok, updated_device} = Updates.enable_updates(device, user)
      assert updated_device.updates_enabled
      assert updated_device.update_attempts == []
    end

    test "triggers DeploymentOrchestratorEvents when device has a deployment_id", %{
      device: device,
      user: user,
      deployment_group: deployment_group
    } do
      {:ok, device} =
        Devices.update_device(device, %{
          deployment_id: deployment_group.id,
          updates_enabled: false
        })

      test_pid = self()

      expect(DeploymentOrchestratorEvents, :device_updated, fn _device ->
        send(test_pid, :orchestrator_notified)
        :ok
      end)

      {:ok, _device} = Updates.enable_updates(device, user)

      assert_receive :orchestrator_notified
    end

    test "does not call DeploymentOrchestratorEvents when device has no deployment_id", %{
      device: device,
      user: user
    } do
      {:ok, device} = Devices.update_device(device, %{deployment_id: nil, updates_enabled: false})

      reject(DeploymentOrchestratorEvents, :device_updated, 1)

      {:ok, _device} = Updates.enable_updates(device, user)
    end
  end

  describe "clear_penalty_box/2" do
    test "resets updates_blocked_until, update_attempts, and enables updates", %{device: device, user: user} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, device} =
        Devices.update_device(device, %{
          updates_blocked_until: future,
          updates_enabled: false,
          update_attempts: [DateTime.utc_now()]
        })

      {:ok, cleared_device} = Updates.clear_penalty_box(device, user)

      assert is_nil(cleared_device.updates_blocked_until)
      assert cleared_device.updates_enabled
      assert cleared_device.update_attempts == []
    end
  end

  describe "toggle_automatic_updates/2" do
    test "disables updates when currently enabled", %{device: device, user: user} do
      {:ok, device} = Devices.update_device(device, %{updates_enabled: true})

      {:ok, updated} = Updates.toggle_automatic_updates(device, user)
      refute updated.updates_enabled
    end

    test "enables updates when currently disabled", %{device: device, user: user} do
      {:ok, device} = Devices.update_device(device, %{updates_enabled: false})

      {:ok, updated} = Updates.toggle_automatic_updates(device, user)
      assert updated.updates_enabled
    end
  end

  # ---- helpers ----

  defp set_different_firmware_uuid(device) do
    firmware_metadata = %{
      architecture: "x86_64",
      platform: "platform",
      product: "valid product",
      version: "0.0.1",
      uuid: Ecto.UUID.generate()
    }

    Devices.update_firmware_metadata(device, firmware_metadata, :unknown, false)
  end

  defp to_device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end
end
