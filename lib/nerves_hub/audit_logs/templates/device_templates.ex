defmodule NervesHub.AuditLogs.DeviceTemplates do
  @moduledoc """
  Templates for and handling of audit logging for device operations.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @reason_max_length 200

  ## General

  @spec audit_reboot(User.t(), Device.t()) :: :ok
  def audit_reboot(user, device) do
    description = "User #{user.name} rebooted device #{device.identifier}"
    AuditLogs.audit!(user, device, description)
  end

  @spec audit_request_action(User.t(), Device.t(), String.t()) :: :ok
  def audit_request_action(user, device, action) do
    description = "User #{user.name} requested the device (#{device.identifier}) #{action}"
    AuditLogs.audit!(user, device, description)
  end

  ## Firmware and upgrades

  @spec audit_update_attempt(Device.t() | DeviceInfo.t()) :: :ok
  def audit_update_attempt(%DeviceInfo{} = device_info) do
    %Device{id: device_info.device_id, identifier: device_info.device_identifier, org_id: device_info.org_id}
    |> audit_update_attempt()
  end

  def audit_update_attempt(%Device{} = device) do
    description = "Device #{device.identifier} is attempting to update"
    AuditLogs.audit(device, device, description)
  end

  @spec audit_pushed_available_update(User.t(), pos_integer | Device.t(), DeploymentGroup.t()) :: :ok
  def audit_pushed_available_update(user, device_id, deployment_group) when is_integer(device_id) do
    device = Devices.get_device(device_id)
    audit_pushed_available_update(user, device, deployment_group)
  end

  def audit_pushed_available_update(user, device, deployment_group) do
    description =
      "User #{user.name} pushed available firmware update #{deployment_group.current_release.firmware.version} #{deployment_group.current_release.firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  @spec audit_firmware_pushed(User.t(), Device.t(), Firmware.t()) :: :ok
  def audit_firmware_pushed(user, device, firmware) do
    description =
      "User #{user.name} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  @spec audit_firmware_metadata_updated(Device.t()) :: :ok
  def audit_firmware_metadata_updated(device) do
    description = "Device #{device.identifier} updated firmware metadata"
    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_validated(Device.t() | DeviceInfo.t()) :: :ok
  def audit_firmware_validated(%DeviceInfo{} = device_info) do
    %Device{id: device_info.device_id, identifier: device_info.device_identifier, org_id: device_info.org_id}
    |> audit_firmware_validated()
  end

  def audit_firmware_validated(%Device{} = device) do
    description = "Device #{device.identifier} has validated its firmware"
    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_upgrade_ignored(Device.t(), DeploymentGroup.t() | nil, String.t() | nil) :: :ok
  def audit_firmware_upgrade_ignored(device, %DeploymentGroup{} = deployment_group, reason) do
    reason = truncate_reason(reason)

    description = """
    Device #{device.identifier} ignored the scheduled firmware upgrade request#{reason && " because of \"#{reason}\""}.
    Firmware upgrades are blocked for #{deployment_group.penalty_timeout_minutes} minutes.
    """

    AuditLogs.audit!(deployment_group, device, description)
  end

  def audit_firmware_upgrade_ignored(device, _deployment_group, reason) do
    reason = truncate_reason(reason)

    description = """
    Device #{device.identifier} ignored the manual firmware upgrade request#{reason && " because of \"#{reason}\""}.
    """

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_upgrade_blocked(DeploymentGroup.t(), Device.t()) :: :ok
  def audit_firmware_upgrade_blocked(deployment_group, device) do
    description = """
    Device #{device.identifier} automatically blocked firmware upgrades for #{deployment_group.penalty_timeout_minutes} minutes.
    Device failure rate met for firmware #{deployment_group.current_release.firmware.uuid} in deployment group #{deployment_group.name}.
    """

    AuditLogs.audit!(deployment_group, device, description)
  end

  @spec audit_firmware_upgrade_rescheduled(Device.t(), NaiveDateTime.t(), String.t() | nil) :: :ok
  def audit_firmware_upgrade_rescheduled(
        %{inflight_update: %{deployment_group: %DeploymentGroup{} = deployment_group}} = device,
        blocked_until,
        reason
      ) do
    reason = truncate_reason(reason)

    description = """
    During an update request from \"#{deployment_group.name}\", device #{device.identifier} requested firmware upgrades be rescheduled #{Timex.from_now(blocked_until)} time #{reason && "because \"#{reason}\""}.
    """

    AuditLogs.audit!(deployment_group, device, description)
  end

  def audit_firmware_upgrade_rescheduled(device, blocked_until, reason) do
    reason = truncate_reason(reason)

    description = """
    During a manual firmware update request, device #{device.identifier} requested firmware upgrades be rescheduled #{Timex.from_now(blocked_until)} time #{reason && "because \"#{reason}\""}.
    The update will not be automatically retried.
    """

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_upgrade_failed(Device.t(), String.t() | nil, Keyword.t()) :: :ok
  def audit_firmware_upgrade_failed(device, reason, opts \\ [])

  def audit_firmware_upgrade_failed(
        %{inflight_update: %{deployment_group: %DeploymentGroup{} = deployment_group}} = device,
        reason,
        opts
      ) do
    reason = truncate_reason(reason)

    description = """
    Device #{device.identifier} reported an error #{reason && "(\"#{reason}\") "}while trying to update its firmware during a deployment release. Updates will be blocked for #{opts[:penalty_timeout_minutes]} minutes.
    """

    AuditLogs.audit!(deployment_group, device, description)
  end

  def audit_firmware_upgrade_failed(device, reason, _opts) do
    reason = truncate_reason(reason)

    description = """
    Device #{device.identifier} reported an error #{reason && "(\"#{reason}\") "}while trying to update its firmware.
    """

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_updated(Device.t()) :: :ok
  def audit_firmware_updated(device) do
    description =
      "Device #{device.identifier} firmware set to version #{device.firmware_metadata.version} (#{device.firmware_metadata.uuid})"

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_device_deployment_group_update_triggered(
          Device.t(),
          DeploymentGroup.t()
        ) :: :ok
  def audit_device_deployment_group_update_triggered(device, deployment_group) do
    firmware = deployment_group.current_release.firmware

    description =
      "Deployment #{deployment_group.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit!(deployment_group, device, description)
  end

  @doc """
  A device that manages its own updates asked for one.

  The device is the actor, which is what separates this in the audit log from an
  update its deployment group pushed.
  """
  @spec audit_device_requested_update(Device.t(), DeploymentGroup.t()) :: :ok
  def audit_device_requested_update(device, deployment_group) do
    firmware = deployment_group.current_release.firmware

    description =
      "Device #{device.identifier} requested firmware #{firmware.uuid} from deployment #{deployment_group.name}"

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_device_deployment_group_update(User.t(), Device.t(), DeploymentGroup.t()) :: :ok
  def audit_device_deployment_group_update(user, device, deployment_group) do
    AuditLogs.audit!(
      user,
      device,
      "User #{user.name} set #{device.identifier}'s deployment group to #{deployment_group.name}"
    )
  end

  @spec audit_set_deployment(Device.t(), DeploymentGroup.t(), :one_found | :multiple_found) :: :ok
  def audit_set_deployment(device, deployment_group, :one_found) do
    AuditLogs.audit!(
      device,
      device,
      "Updating #{device.identifier}'s deployment group to #{deployment_group.name}"
    )
  end

  def audit_set_deployment(device, deployment_group, :multiple_found) do
    AuditLogs.audit!(
      device,
      device,
      "Multiple matching deployments found, updating #{device.identifier}'s deployment group to #{deployment_group.name}"
    )
  end

  @spec audit_device_archive_update_triggered(Device.t(), Archive.t(), UUIDv7.t()) :: :ok
  def audit_device_archive_update_triggered(device, archive, reference_id) do
    description =
      "Archive update triggered for #{device.identifier}. Sending archive #{archive.uuid}."

    AuditLogs.audit_with_ref!(device, device, description, reference_id)

    :ok
  end

  # Failure reasons come straight off the device socket payload, so they are
  # unbounded. Cap them before they reach a description, and keep `nil` as
  # `nil` so the templates can omit the reason clause entirely.
  defp truncate_reason(nil), do: nil

  defp truncate_reason(reason) when is_binary(reason) do
    if String.length(reason) > @reason_max_length do
      String.slice(reason, 0, @reason_max_length - 1) <> "…"
    else
      reason
    end
  end
end
