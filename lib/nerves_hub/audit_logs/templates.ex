defmodule NervesHub.AuditLogs.Templates do
  alias NervesHub.AuditLogs

  require Logger

  def audit_resolve_changed_deployment(device, reference_id) do
    description =
      if device.deployment_id do
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment_group.name}"
      else
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
      end

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end

  def audit_device_deployment_update_triggered(device, reference_id) do
    deployment_group = device.deployment_group
    firmware = deployment_group.firmware

    description =
      "deployment #{deployment_group.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit_with_ref!(deployment_group, device, description, reference_id)
  end

  def audit_device_assigned(device, reference_id) do
    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment_group.name}"

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end

  def audit_unsupported_api_version(device) do
    description =
      "device #{device.identifier} could not get extensions: Unsupported API version."

    AuditLogs.audit!(device, device, description)
    Logger.info("[DeviceChannel] #{description}")
  end
end
