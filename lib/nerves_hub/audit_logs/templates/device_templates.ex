defmodule NervesHub.AuditLogs.DeviceTemplates do
  @moduledoc """
  Templates for and handling of audit logging for device operations.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

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

  @spec audit_update_attempt(Device.t()) :: :ok
  def audit_update_attempt(device) do
    description = "Device #{device.identifier} is attempting to update"
    AuditLogs.audit(device, device, description)
  end

  @spec audit_pushed_available_update(User.t(), Device.t(), DeploymentGroup.t()) :: :ok
  def audit_pushed_available_update(user, device, deployment_group) do
    description =
      "User #{user.name} pushed available firmware update #{deployment_group.firmware.version} #{deployment_group.firmware.uuid} to device #{device.identifier}"

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

  @spec audit_firmware_validated(Device.t()) :: :ok
  def audit_firmware_validated(device) do
    description = "Device #{device.identifier} has validated its firmware"
    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_upgrade_blocked(DeploymentGroup.t(), Device.t()) :: :ok
  def audit_firmware_upgrade_blocked(deployment_group, device) do
    description = """
    Device #{device.identifier} automatically blocked firmware upgrades for #{deployment_group.penalty_timeout_minutes} minutes.
    Device failure rate met for firmware #{deployment_group.firmware.uuid} in deployment group #{deployment_group.name}.
    """

    AuditLogs.audit!(deployment_group, device, description)
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
    firmware = deployment_group.firmware

    description =
      "Deployment #{deployment_group.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit!(deployment_group, device, description)
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
end
