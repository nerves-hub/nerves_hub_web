defmodule NervesHub.AuditLogs.Templates do
  alias NervesHub.AuditLogs

  def audit_resolve_changed_deployment(device, reference_id) do
    description =
      if device.deployment_id do
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"
      else
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
      end

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end

  def audit_device_deployment_update_triggered(device, reference_id) do
    deployment = device.deployment
    firmware = deployment.firmware

    description =
      "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

    AuditLogs.audit_with_ref!(deployment, device, description, reference_id)
  end

  def audit_device_assigned(device, reference_id) do
    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit_with_ref!(device, device, description, reference_id)
  end
end
