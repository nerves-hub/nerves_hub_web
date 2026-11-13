defmodule NervesHub.Webhooks.Payloads do
  @moduledoc """
  The `data` of each webhook event, built from whatever the code raising the
  event has in hand.

  These shapes are what receivers are written against, so they live together
  here, and `docs/webhooks.md` shows each one. Adding a key is safe; renaming
  or removing one breaks an integration this repository cannot see.

  Every event about a device carries `device`: its identifier and the firmware
  it is running as far as NervesHub knows. `NervesHub.Integrations.dispatch/3`
  adds `org` and `product`.

  Each function runs only when an integration wants its event (it is the
  function passed to `dispatch/3`), so the queries some of them make cost
  nothing for products without one.
  """

  import Ecto.Query

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo

  @doc "`device.connected`"
  @spec device_connected(DeviceConnection.t()) :: map()
  def device_connected(%DeviceConnection{} = connection) do
    %{
      device: device(connection.device_id),
      connection: %{id: connection.id, established_at: connection.established_at}
    }
  end

  @doc """
  `device.disconnected`

  `devices` is the device summaries for a batch of connections, by device id,
  for the stale connection sweep, which closes many at once.
  """
  @spec device_disconnected(DeviceConnection.t(), %{optional(pos_integer()) => map()}) :: map()
  def device_disconnected(%DeviceConnection{} = connection, devices \\ %{}) do
    %{
      device: Map.get_lazy(devices, connection.device_id, fn -> device(connection.device_id) end),
      connection: %{
        id: connection.id,
        established_at: connection.established_at,
        disconnected_at: connection.disconnected_at,
        reason: connection.disconnected_reason
      }
    }
  end

  @doc """
  `device.health_reported`

  `metrics` is the readings as stored (`NervesHub.Devices.Metrics.storable/1`);
  alarms and metadata are passed on as the device sent them.
  """
  @spec health_reported(DeviceInfo.t(), map(), map()) :: map()
  def health_reported(%DeviceInfo{} = device_info, metrics, report) do
    %{
      device: device(device_info),
      metrics: metrics,
      alarms: map_or_empty(report["alarms"]),
      metadata: map_or_empty(report["metadata"])
    }
  end

  @doc """
  `device.metrics_reported`

  `reports` is the batch's readings with their timestamps, one entry per
  report the device sent and NervesHub stored.
  """
  @spec metrics_reported(DeviceInfo.t(), [%{timestamp: DateTime.t(), metrics: map()}]) :: map()
  def metrics_reported(%DeviceInfo{} = device_info, reports) do
    %{device: device(device_info), reports: reports}
  end

  @doc """
  `device.health_status_changed`

  `previous_status` is `nil` for a device's first verdict. `reasons` names
  each metric holding the device at warning or unhealthy, as stored.
  """
  @spec health_status_changed(DeviceInfo.t(), atom() | nil, DeviceHealth.t()) :: map()
  def health_status_changed(%DeviceInfo{} = device_info, previous_status, %DeviceHealth{} = health) do
    %{
      device: device(device_info),
      status: Atom.to_string(health.status),
      previous_status: previous_status && Atom.to_string(previous_status),
      reasons: health.status_reasons
    }
  end

  @doc """
  `device.firmware_update.scheduled`

  `initiated_by` is `"deployment_group"`, `"user"` or `"device"`.
  """
  @spec firmware_update_scheduled(Device.t(), Firmware.t(), String.t(), DeploymentGroup.t() | nil) :: map()
  def firmware_update_scheduled(%Device{} = device, %Firmware{} = firmware, initiated_by, deployment_group) do
    %{
      device: device(device),
      firmware: %{uuid: firmware.uuid, version: firmware.version},
      initiated_by: initiated_by,
      deployment_group: deployment_group && %{name: deployment_group.name}
    }
  end

  @doc """
  `device.firmware_update.progress`

  `progress` is a percentage, for the stages that report one.
  """
  @spec firmware_update_progress(map(), String.t(), integer() | nil, String.t() | nil) :: map()
  def firmware_update_progress(device, status, progress, target_firmware_uuid) do
    %{
      device: device(device),
      status: status,
      progress: progress,
      firmware: firmware(device.product_id, target_firmware_uuid)
    }
  end

  @doc """
  `device.firmware_update.finished`

  `opts` are those of `NervesHub.Devices.UpdateHistory.record/3`.
  """
  @spec firmware_update_finished(map(), atom(), keyword()) :: map()
  def firmware_update_finished(device, outcome, opts) do
    %{
      device: device(device),
      outcome: Atom.to_string(outcome),
      reason: opts[:reason],
      source_firmware: firmware(device.product_id, opts[:source_firmware_uuid]),
      target_firmware: firmware(device.product_id, opts[:target_firmware_uuid]),
      deployment_group: deployment_group(opts[:deployment_id])
    }
  end

  @doc "`device.firmware_validated`"
  @spec firmware_validated(DeviceInfo.t()) :: map()
  def firmware_validated(%DeviceInfo{} = device_info) do
    %{device: device(device_info)}
  end

  @doc """
  `error_group.created` and `error_group.reopened`

  About an error rather than one device, so there is no `device`. `group` is
  the error group as `NervesHub.ErrorReports.GroupBuffer` wrote it.
  """
  @spec error_group(map()) :: map()
  def error_group(group) do
    %{
      error: %{
        id: group.id,
        kind: group.kind,
        source: group.source,
        reason: group.reason,
        top_frame: top_frame(group),
        occurrence_count: group.occurrence_count,
        first_seen_at: group.first_seen_at,
        last_seen_at: group.last_seen_at
      }
    }
  end

  @doc """
  `deployment_group.workflow_step.started`, `.awaiting_approval`,
  `.completed`, `.failed` and `.skipped`

  About a deployment group's workflow rather than one device, so there is no
  `device`. `release` is what `NervesHub.ManagedDeployments.WorkflowEvents`
  read of the step's release. `user` is who skipped, retried or approved the
  step, and `nil` when the workflow moved on its own; `failed_devices` is
  set only for a failed step.
  """
  @spec workflow_step(DeploymentWorkflowStep.t(), map(), keyword()) :: map()
  def workflow_step(%DeploymentWorkflowStep{} = step, release, opts) do
    step_count =
      DeploymentWorkflowStep
      |> where([s], s.deployment_release_id == ^step.deployment_release_id)
      |> Repo.aggregate(:count)

    %{
      deployment_group: release.deployment_group,
      release: %{number: release.number, firmware: release.firmware},
      workflow: %{steps: step_count},
      step: %{
        id: step.id,
        number: step.number,
        name: DeploymentWorkflowStep.label(step),
        type: Atom.to_string(step.type),
        status: Atom.to_string(step.status),
        started_at: utc(step.started_at),
        finished_at: utc(step.finished_at)
      },
      user: opts[:user] && %{name: opts[:user].name},
      failed_devices: opts[:failed_devices]
    }
  end

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp top_frame(%{top_frame_module: nil, top_frame_function: nil}), do: nil

  defp top_frame(group) do
    name = [group.top_frame_module, group.top_frame_function] |> Enum.reject(&is_nil/1) |> Enum.join(".")
    location = if group.top_frame_file, do: " (#{group.top_frame_file}:#{group.top_frame_line})", else: ""
    name <> location
  end

  @doc """
  Device summaries for a batch of device ids, by id, in one query.
  """
  @spec devices([pos_integer()]) :: %{optional(pos_integer()) => map()}
  def devices(device_ids) do
    Device
    |> where([d], d.id in ^device_ids)
    |> select([d], {d.id, d.identifier, d.firmware_metadata})
    |> Repo.all()
    |> Map.new(fn {id, identifier, firmware_metadata} -> {id, summary(identifier, firmware_metadata)} end)
  end

  # Whatever the caller has: a connection's `DeviceInfo`, a device or the
  # partial device `NervesHub.FirmwareUpdates` carries, or only an id (or a
  # map with only an id), which costs a query.
  defp device(%DeviceInfo{} = device_info) do
    summary(device_info.device_identifier, device_info.firmware_metadata)
  end

  defp device(%{identifier: identifier, firmware_metadata: firmware_metadata}) do
    summary(identifier, firmware_metadata)
  end

  defp device(%{id: id}), do: device(id)

  defp device(id) when is_integer(id) do
    Map.get(devices([id]), id, %{identifier: nil, firmware: nil})
  end

  defp summary(identifier, firmware_metadata) do
    %{identifier: identifier, firmware: firmware_metadata(firmware_metadata)}
  end

  defp firmware_metadata(nil), do: nil

  defp firmware_metadata(metadata) do
    %{
      uuid: Map.get(metadata, :uuid),
      version: Map.get(metadata, :version),
      platform: Map.get(metadata, :platform),
      architecture: Map.get(metadata, :architecture)
    }
  end

  # The version is what a person reads; the uuid is what identifies it. Firmware
  # deleted since is still named by its uuid.
  defp firmware(_product_id, nil), do: nil

  defp firmware(product_id, uuid) do
    version =
      Firmware
      |> where([f], f.product_id == ^product_id and f.uuid == ^uuid)
      |> select([f], f.version)
      |> Repo.one()

    %{uuid: uuid, version: version}
  end

  defp deployment_group(nil), do: nil

  defp deployment_group(id) do
    DeploymentGroup
    |> where([dg], dg.id == ^id)
    |> select([dg], %{name: dg.name})
    |> Repo.one()
  end

  defp map_or_empty(map) when is_map(map), do: map
  defp map_or_empty(_other), do: %{}
end
