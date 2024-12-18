defmodule NervesHub.AuditLogs.Templates do
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices.Device

  require Logger

  ### RESOURCE: DEVICE

  ## General

  def audit_reboot(user, device) do
    description = "#{user.name} rebooted device #{device.identifier}"
    AuditLogs.audit!(user, device, description)
  end

  def audit_request_action(user, device, action) do
    description = "#{user.name} requested the device (#{device.identifier}) #{action}"
    AuditLogs.audit!(user, device, description)
  end

  def audit_unsupported_api_version(device) do
    description =
      "device #{device.identifier} could not get extensions: Unsupported API version."

    AuditLogs.audit!(device, device, description)
    Logger.info("[DeviceChannel] #{description}")
  end

  ## Firmware and upgrades
  # Deprecated?
  def audit_device_assigned(device, reference_id) do
    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end

  # Deprecated?
  def audit_resolve_changed_deployment(device, reference_id) do
    description =
      if device.deployment_id do
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"
      else
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
      end

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end

  def audit_update_attempt(device) do
    description = "device #{device.identifier} is attempting to update"
    AuditLogs.audit(device, device, description)
  end

  def audit_pushed_available_update(user, device, deployment) do
    description =
      "#{user.name} pushed available firmware update #{deployment.firmware.version} #{deployment.firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  def audit_firmware_pushed(user, device, firmware) do
    description =
      "#{user.name} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)
  end

  def audit_firmware_metadata_updated(device) do
    description = "device #{device.identifier} updated firmware metadata"
    AuditLogs.audit!(device, device, description)
  end

  def audit_firmware_upgrade_blocked(deployment, device) do
    description = """
    Device #{device.identifier} automatically blocked firmware upgrades for #{deployment.penalty_timeout_minutes} minutes.
    Device failure rate met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}.
    """

    AuditLogs.audit!(deployment, device, description)
  end

  def audit_firmware_updated(device) do
    description =
      "device #{device.identifier} firmware set to version #{device.firmware_metadata.version} (#{device.firmware_metadata.uuid})"

    AuditLogs.audit!(device, device, description)
  end

  def audit_device_deployment_update_triggered(device, reference_id) do
    deployment = device.deployment
    firmware = deployment.firmware

    description =
      "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit_with_ref!(deployment, device, description, reference_id)
  end

  ### RESOUCE: DEPLOYMENT

  def audit_deployment_created(user, deployment) do
    description = "#{user.name} created deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  def audit_deployment_updated(user, deployment) do
    description = "#{user.name} updated deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  def audit_deployment_deleted(user, deployment) do
    description = "#{user.name} deleted deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  def audit_deployment_toggle_active(user, deployment, status) do
    description = "#{user.name} marked deployment #{deployment.name} #{status}"
    AuditLogs.audit!(user, deployment, description)
  end

  def audit_deployment_mismatch(device, deployment, reason) do
    description =
      "device no longer matches deployment #{deployment.name}'s requirements because of #{reason}"

    AuditLogs.audit!(device, deployment, description)
  end

  def audit_deployment_change(deployment, change_string) do
    description = "deployment #{deployment.name} #{change_string}"
    AuditLogs.audit!(deployment, deployment, description)
  end

  @spec audit_device_deployment_update(User.t(), Device.t(), Deployment.t()) :: AuditLog.t()
  def audit_device_deployment_update(user, device, deployment) do
    AuditLogs.audit!(
      user,
      device,
      "#{user.name} set #{device.identifier}'s deployment to #{deployment.name}"
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

  def audit_set_deployment(device, deployment, :multiple_found) do
    AuditLogs.audit!(
      device,
      device,
      "Multiple matching deployments found, updating #{device.identifier}'s deployment to #{deployment.name}"
    )
  end
end
