defmodule NervesHub.AuditLogs.DeviceTemplates do
  @moduledoc """
  Templates for and handling of audit logging for device operations.

  Each description is a `NervesHub.AuditLogs.Template`, so the web UI names
  the users, devices, deployment groups, firmware and archives in it as they
  are when the entry is read, with a link to each.
  """

  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Template
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Helpers.RelativeTime
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @reason_max_length 200

  ## General

  # `via` names where a request came from when it was not the dashboard or
  # the API, such as Slack.
  @spec audit_reboot(AuditLogs.actor(), Device.t(), String.t() | nil) :: :ok
  def audit_reboot(actor, device, via \\ nil) do
    template = via_template("%{actor} rebooted device %{resource}", via)
    AuditLogs.audit!(actor, device, template, kind: :device_rebooted)
  end

  @spec audit_request_action(AuditLogs.actor(), Device.t(), :identify | :reconnect, String.t() | nil) :: :ok
  def audit_request_action(actor, device, action, via \\ nil) do
    {wording, kind} =
      case action do
        :identify -> {"identify itself", :identify_requested}
        :reconnect -> {"reconnect", :reconnect_requested}
      end

    template = via_template("%{actor} requested the device (%{resource}) #{wording}", via)
    AuditLogs.audit!(actor, device, template, kind: kind)
  end

  @spec audit_script_run(AuditLogs.actor(), Device.t(), String.t(), String.t() | nil) :: :ok
  def audit_script_run(actor, device, script_name, via \\ nil) do
    template =
      via_template("%{actor} ran support script %{script} on device %{resource}", via, script: script_name)

    AuditLogs.audit!(actor, device, template, kind: :script_run)
  end

  defp via_template(text, via, values \\ [])
  defp via_template(text, nil, values), do: Template.new(text, values)
  defp via_template(text, via, values), do: Template.new(text <> " from %{via}", [via: via] ++ values)

  ## Shared secrets

  @spec audit_shared_secret_created(AuditLogs.actor(), Device.t(), SharedSecretAuth.t()) :: :ok
  def audit_shared_secret_created(actor, device, auth) do
    template = Template.new("%{actor} created shared secret %{key} for device %{resource}", key: auth.key)
    AuditLogs.audit!(actor, device, template, kind: :shared_secret_created)
  end

  @spec audit_shared_secret_deactivated(AuditLogs.actor(), Device.t(), SharedSecretAuth.t()) :: :ok
  def audit_shared_secret_deactivated(actor, device, auth) do
    template = Template.new("%{actor} deactivated shared secret %{key} for device %{resource}", key: auth.key)
    AuditLogs.audit!(actor, device, template, kind: :shared_secret_deactivated)
  end

  ## Firmware and upgrades

  @spec audit_update_attempt(Device.t() | DeviceInfo.t()) :: :ok
  def audit_update_attempt(%DeviceInfo{} = device_info) do
    %Device{id: device_info.device_id, identifier: device_info.device_identifier, org_id: device_info.org_id}
    |> audit_update_attempt()
  end

  def audit_update_attempt(%Device{} = device) do
    template = Template.new("Device %{resource} is attempting to update")
    AuditLogs.audit(device, device, template, kind: :update_attempted)
  end

  @spec audit_pushed_available_update(AuditLogs.actor(), Device.t(), Firmware.t()) :: :ok
  def audit_pushed_available_update(actor, device, firmware) do
    template =
      Template.new("%{actor} pushed available firmware update %{version} %{firmware} to device %{resource}",
        version: firmware.version,
        firmware: firmware
      )

    AuditLogs.audit!(actor, device, template, kind: :firmware_pushed)
  end

  @spec audit_firmware_pushed(AuditLogs.actor(), Device.t(), Firmware.t()) :: :ok
  def audit_firmware_pushed(actor, device, firmware) do
    template =
      Template.new("%{actor} pushed firmware %{version} %{firmware} to device %{resource}",
        version: firmware.version,
        firmware: firmware
      )

    AuditLogs.audit!(actor, device, template, kind: :firmware_pushed)
  end

  @spec audit_firmware_metadata_updated(Device.t()) :: :ok
  def audit_firmware_metadata_updated(device) do
    template = Template.new("Device %{resource} updated firmware metadata")
    AuditLogs.audit!(device, device, template, kind: :firmware_metadata_updated)
  end

  @spec audit_firmware_validated(Device.t() | DeviceInfo.t()) :: :ok
  def audit_firmware_validated(%DeviceInfo{} = device_info) do
    %Device{id: device_info.device_id, identifier: device_info.device_identifier, org_id: device_info.org_id}
    |> audit_firmware_validated()
  end

  def audit_firmware_validated(%Device{} = device) do
    template = Template.new("Device %{resource} has validated its firmware")
    AuditLogs.audit!(device, device, template, kind: :firmware_validated)
  end

  @spec audit_firmware_upgrade_ignored(Device.t(), DeploymentGroup.t() | nil, String.t() | nil) :: :ok
  def audit_firmware_upgrade_ignored(device, %DeploymentGroup{} = deployment_group, reason) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        Device %{resource} ignored the scheduled firmware upgrade request#{reason && " because of \"%{reason}\""}.
        Firmware upgrades are blocked for %{minutes} minutes.
        """,
        reason: reason,
        minutes: deployment_group.penalty_timeout_minutes
      )

    AuditLogs.audit!(deployment_group, device, template, kind: :update_ignored)
  end

  def audit_firmware_upgrade_ignored(device, _deployment_group, reason) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        Device %{resource} ignored the manual firmware upgrade request#{reason && " because of \"%{reason}\""}.
        """,
        reason: reason
      )

    AuditLogs.audit!(device, device, template, kind: :update_ignored)
  end

  @spec audit_firmware_upgrade_blocked(DeploymentGroup.t(), Device.t(), Firmware.t()) :: :ok
  def audit_firmware_upgrade_blocked(deployment_group, device, firmware) do
    template =
      Template.new(
        """
        Device %{resource} automatically blocked firmware upgrades for %{minutes} minutes.
        Device failure rate met for firmware %{firmware} in deployment group %{actor}.
        """,
        minutes: deployment_group.penalty_timeout_minutes,
        firmware: firmware
      )

    AuditLogs.audit!(deployment_group, device, template, kind: :updates_blocked)
  end

  @spec audit_firmware_upgrade_rescheduled(Device.t(), NaiveDateTime.t(), String.t() | nil) :: :ok
  def audit_firmware_upgrade_rescheduled(
        %{inflight_update: %{deployment_group: %DeploymentGroup{} = deployment_group}} = device,
        blocked_until,
        reason
      ) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        During an update request from \"%{actor}\", device %{resource} requested firmware upgrades be rescheduled %{until} time #{reason && "because \"%{reason}\""}.
        """,
        until: RelativeTime.from_now(blocked_until),
        reason: reason
      )

    AuditLogs.audit!(deployment_group, device, template, kind: :update_rescheduled)
  end

  def audit_firmware_upgrade_rescheduled(device, blocked_until, reason) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        During a manual firmware update request, device %{resource} requested firmware upgrades be rescheduled %{until} time #{reason && "because \"%{reason}\""}.
        The update will not be automatically retried.
        """,
        until: RelativeTime.from_now(blocked_until),
        reason: reason
      )

    AuditLogs.audit!(device, device, template, kind: :update_rescheduled)
  end

  @spec audit_firmware_upgrade_failed(Device.t(), String.t() | nil, Keyword.t()) :: :ok
  def audit_firmware_upgrade_failed(device, reason, opts \\ [])

  def audit_firmware_upgrade_failed(
        %{inflight_update: %{deployment_group: %DeploymentGroup{} = deployment_group}} = device,
        reason,
        opts
      ) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        Device %{resource} reported an error #{reason && "(\"%{reason}\") "}while trying to update its firmware during a deployment release. Updates will be blocked for %{minutes} minutes.
        """,
        reason: reason,
        minutes: opts[:penalty_timeout_minutes]
      )

    AuditLogs.audit!(deployment_group, device, template, kind: :update_failed)
  end

  def audit_firmware_upgrade_failed(device, reason, _opts) do
    reason = truncate_reason(reason)

    template =
      Template.new(
        """
        Device %{resource} reported an error #{reason && "(\"%{reason}\") "}while trying to update its firmware.
        """,
        reason: reason
      )

    AuditLogs.audit!(device, device, template, kind: :update_failed)
  end

  @spec audit_firmware_updated(Device.t()) :: :ok
  def audit_firmware_updated(device) do
    template =
      Template.new("Device %{resource} firmware set to version %{version} (%{firmware})",
        version: device.firmware_metadata.version,
        firmware: device.firmware_metadata
      )

    AuditLogs.audit!(device, device, template, kind: :firmware_updated)
  end

  @spec audit_device_deployment_group_update_triggered(
          Device.t(),
          DeploymentGroup.t(),
          Firmware.t()
        ) :: :ok
  def audit_device_deployment_group_update_triggered(device, deployment_group, firmware) do
    template =
      Template.new("Deployment %{actor} update triggered device %{resource} to update firmware %{firmware}",
        firmware: firmware
      )

    AuditLogs.audit!(deployment_group, device, template, kind: :deployment_update_sent)
  end

  @doc """
  A device that manages its own updates asked for one.

  The device is the actor, which is what separates this in the audit log from an
  update its deployment group pushed.
  """
  @spec audit_device_requested_update(Device.t(), DeploymentGroup.t(), Firmware.t()) :: :ok
  def audit_device_requested_update(device, deployment_group, firmware) do
    template =
      Template.new("Device %{resource} requested firmware %{firmware} from deployment %{deployment_group}",
        firmware: firmware,
        deployment_group: deployment_group
      )

    AuditLogs.audit!(device, device, template, kind: :update_requested)
  end

  @spec audit_device_deployment_group_update(AuditLogs.actor(), Device.t(), DeploymentGroup.t()) :: :ok
  def audit_device_deployment_group_update(actor, device, deployment_group) do
    AuditLogs.audit!(
      actor,
      device,
      Template.new("%{actor} set %{resource}'s deployment group to %{deployment_group}",
        deployment_group: deployment_group
      ),
      kind: :deployment_group_set
    )
  end

  @spec audit_set_deployment(Device.t(), DeploymentGroup.t(), :one_found | :multiple_found) :: :ok
  def audit_set_deployment(device, deployment_group, :one_found) do
    AuditLogs.audit!(
      device,
      device,
      Template.new("Updating %{resource}'s deployment group to %{deployment_group}",
        deployment_group: deployment_group
      ),
      kind: :deployment_group_set
    )
  end

  def audit_set_deployment(device, deployment_group, :multiple_found) do
    AuditLogs.audit!(
      device,
      device,
      Template.new(
        "Multiple matching deployments found, updating %{resource}'s deployment group to %{deployment_group}",
        deployment_group: deployment_group
      ),
      kind: :deployment_group_set
    )
  end

  @spec audit_device_archive_update_triggered(Device.t(), Archive.t(), Ecto.UUID.t()) :: :ok
  def audit_device_archive_update_triggered(device, archive, reference_id) do
    template = Template.new("Archive update triggered for %{resource}. Sending archive %{archive}.", archive: archive)

    AuditLogs.audit_with_ref!(device, device, template, reference_id, kind: :archive_sent)

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
