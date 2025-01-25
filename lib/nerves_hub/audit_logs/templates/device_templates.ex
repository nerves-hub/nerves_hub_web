defmodule NervesHub.AuditLogs.DeviceTemplates do
  @moduledoc """
  Templates for and handling of audit logging for device operations.
  """
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware

  require Logger

  ## General

  @spec audit_reboot(User.t(), Device.t()) :: AuditLog.t()
  def audit_reboot(user, device) do
    description = "User #{user.name} rebooted device #{device.identifier}"
    AuditLogs.audit!(user, device, description)
  end

  @spec audit_request_action(User.t(), Device.t(), String.t()) :: AuditLog.t()
  def audit_request_action(user, device, action) do
    description = "User #{user.name} requested the device (#{device.identifier}) #{action}"
    AuditLogs.audit!(user, device, description)
  end

  ## Firmware and upgrades

  @spec audit_update_attempt(Device.t()) :: AuditLog.t()
  def audit_update_attempt(device) do
    description = "Device #{device.identifier} is attempting to update"
    AuditLogs.audit(device, device, description)
  end

  @spec audit_pushed_available_update(User.t(), Device.t(), Deployment.t()) :: AuditLog.t()
  def audit_pushed_available_update(user, device, deployment) do
    description =
      "User #{user.name} pushed available firmware update #{deployment.firmware.version} #{deployment.firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  @spec audit_firmware_pushed(User.t(), Device.t(), Firmware.t()) :: AuditLog.t()
  def audit_firmware_pushed(user, device, firmware) do
    description =
      "User #{user.name} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  @spec audit_firmware_metadata_updated(Device.t()) :: AuditLog.t()
  def audit_firmware_metadata_updated(device) do
    description = "Device #{device.identifier} updated firmware metadata"
    AuditLogs.audit!(device, device, description)
  end

  @spec audit_firmware_upgrade_blocked(Deployment.t(), Device.t()) :: AuditLog.t()
  def audit_firmware_upgrade_blocked(deployment, device) do
    description = """
    Device #{device.identifier} automatically blocked firmware upgrades for #{deployment.penalty_timeout_minutes} minutes.
    Device failure rate met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}.
    """

    AuditLogs.audit!(deployment, device, description)
  end

  @spec audit_firmware_updated(Device.t()) :: AuditLog.t()
  def audit_firmware_updated(device) do
    description =
      "Device #{device.identifier} firmware set to version #{device.firmware_metadata.version} (#{device.firmware_metadata.uuid})"

    AuditLogs.audit!(device, device, description)
  end

  @spec audit_device_deployment_update_triggered(Device.t(), UUIDv7.t()) :: AuditLog.t()
  def audit_device_deployment_update_triggered(device, reference_id) do
    deployment = device.deployment
    firmware = deployment.firmware

    description =
      "Deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit_with_ref!(deployment, device, description, reference_id)
  end

  @spec audit_device_deployment_update(User.t(), Device.t(), Deployment.t()) :: AuditLog.t()
  def audit_device_deployment_update(user, device, deployment) do
    AuditLogs.audit!(
      user,
      device,
      "User #{user.name} set #{device.identifier}'s deployment to #{deployment.name}"
    )
  end

  @spec audit_device_deployment_update(Device.t(), Deployment.t(), :one_found | :multiple_found) ::
          AuditLog.t()
  def audit_set_deployment(device, deployment, :one_found) do
    AuditLogs.audit!(
      device,
      device,
      "Updating #{device.identifier}'s deployment to #{deployment.name}"
    )
  end

  @spec audit_set_deployment(Device.t(), Deployment.t(), :one_found | :multiple_found) ::
          AuditLog.t()
  def audit_set_deployment(device, deployment, :multiple_found) do
    AuditLogs.audit!(
      device,
      device,
      "Multiple matching deployments found, updating #{device.identifier}'s deployment to #{deployment.name}"
    )
  end
end
