defmodule NervesHub.Devices.Updates do
  @moduledoc """
  Device update-orchestration context.

  This module owns the logic that decides whether and what to update a device
  with: finding devices that are available for (priority) updates, resolving the
  update payload for a device, verifying update eligibility, managing the penalty
  box, and recording update attempts.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  require Logger

  def firmware_validated(device_info) do
    Repo.transact(fn ->
      with device when not is_nil(device) <- Devices.get_device(device_info.device_id),
           device_changeset = Device.firmware_validated(device),
           {:ok, device} <- Repo.update(device_changeset),
           device_firmware_changeset = DeviceFirmware.firmware_validated(device),
           {:ok, _device_firmware} <- Repo.update(device_firmware_changeset),
           :ok <- DeviceTemplates.audit_firmware_validated(device_info) do
        {:ok, device}
      end
    end)

    PubSub.broadcast(device_info.device_id, "firmware:validated", %{})

    :ok
  end

  @doc """
  Fetch devices associated with a deployment for updating.

  Devices must be:
  - online
  - have automatic updates enabled
  - not currently updating
  - not be running the same firmware version associated with the deployment
  - not in the penalty box (based on `updates_blocked_until`)

  If the deployment group has `enable_priority_updates` set to false (the default),
  devices are ordered by their `latest_connection`: devices connected the longest will
  be updated first.

  If the deployment group has `enable_priority_updates` set to true,
  devices are ordered by most recently connected for the first time (`device.first_seen_at`)
  """
  @spec available_for_update(DeploymentGroup.t(), non_neg_integer()) :: [Device.t()]
  def available_for_update(deployment_group, count) do
    build_available_devices_query(deployment_group, count, [])
    |> Repo.all()
  end

  @doc """
  Get devices eligible for priority queue updates.

  Similar to `available_for_update/2` but filters devices whose firmware version
  is less than or equal to the priority_queue_firmware_version_threshold.
  """
  @spec available_for_priority_update(DeploymentGroup.t(), non_neg_integer()) :: [Device.t()]

  # No threshold set, return empty list
  def available_for_priority_update(%DeploymentGroup{priority_queue_firmware_version_threshold: threshold}, _count)
      when is_nil(threshold), do: []

  def available_for_priority_update(deployment_group, count) do
    threshold = deployment_group.priority_queue_firmware_version_threshold

    build_available_devices_query(deployment_group, count, version_threshold: threshold)
    |> Repo.all()
  end

  # Builds the query for finding available devices for updates
  # Options:
  #   - :version_threshold - Optional firmware version threshold for priority queue filtering
  defp build_available_devices_query(deployment_group, count, opts) do
    now = DateTime.utc_now(:second)
    version_threshold = Keyword.get(opts, :version_threshold)

    Device
    |> from(as: :device)
    |> join(:inner, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> join(:inner, [d], dg in assoc(d, :deployment_group), as: :deployment_group)
    |> join(:left, [d], ifu in InflightUpdate, on: d.id == ifu.device_id, as: :inflight_update)
    |> ManagedDeployments.join_current_release()
    |> join_firmware()
    |> join_firmware_deltas()
    |> where([device: d], d.deployment_id == ^deployment_group.id)
    |> where([device: d], d.update_mode == :automatic)
    |> where([device: d], not is_nil(d.firmware_metadata))
    |> where([device: d], d.firmware_validation_status in [:validated, :unknown])
    |> where([device: d], coalesce(d.updates_blocked_until, "1970-01-01 00:00:00") |> type(:naive_datetime) < ^now)
    |> where([deployment_group: dg], dg.is_active == true)
    |> where([deployment_group: dg], dg.status == :ready)
    # this is a short circuit to avoid a race condition where a new deployment release is created by
    # the orchestrator is about to run this query before the orchestrator has refreshed its information
    |> where(
      [deployment_group: dg],
      dg.current_deployment_release_id == ^deployment_group.current_deployment_release_id
    )
    |> where([latest_connection: lc], lc.status == :connected)
    |> where([firmware: f, current_release: cr], is_nil(f.id) or f.id != cr.firmware_id)
    |> where([inflight_update: ifu], is_nil(ifu))
    # Only include devices where: delta is completed OR no delta row exists
    |> where([firmware_delta: fd], is_nil(fd.id) or fd.status == :completed)
    |> maybe_version_threshold(version_threshold)
    |> maybe_filter_by_network_interfaces(deployment_group.release_network_interfaces)
    |> maybe_release_tags(deployment_group.release_tags)
    |> order_by_queue_management(deployment_group.queue_management)
    |> limit(^count)
  end

  defp join_firmware(query) do
    join(query, :left, [d], f in Firmware,
      on: f.product_id == d.product_id and f.uuid == fragment("(? #>> '{\"uuid\"}')", d.firmware_metadata),
      as: :firmware
    )
  end

  defp join_firmware_deltas(query) do
    join(query, :left, [firmware: f, current_release: cr], fd in FirmwareDelta,
      on: fd.source_id == f.id and fd.target_id == cr.firmware_id,
      as: :firmware_delta
    )
  end

  # Filter by network interface if release_network_interfaces is specified
  # Empty list means allow all interfaces
  defp maybe_filter_by_network_interfaces(query, []) do
    query
  end

  defp maybe_filter_by_network_interfaces(query, interfaces) do
    where(query, [latest_connection: lc], lc.network_interface in ^interfaces)
  end

  defp maybe_version_threshold(query, nil), do: query

  # Eligible when the device's reported version is at or below the threshold.
  # Uses `semver_sort_key/1` (SemVer precedence via byte ordering) under
  # `COLLATE "C"` — the DB's `en_US.utf8` default would invert pre-release order.
  # A non-semver device version yields a NULL key, so the comparison is NULL and
  # the device is excluded (quarantined) rather than raising, as the previous
  # `semver_match` did when casting a malformed version to int[].
  defp maybe_version_threshold(query, version_threshold) do
    where(
      query,
      [d],
      fragment(
        ~s|semver_sort_key(? #>> '{"version"}') COLLATE "C" <= semver_sort_key(?) COLLATE "C"|,
        d.firmware_metadata,
        ^version_threshold
      )
    )
  end

  defp maybe_release_tags(query, release_tags) when release_tags != [] do
    where(query, [d], fragment("? @> ?", d.tags, ^release_tags))
  end

  defp maybe_release_tags(query, _release_tags), do: query

  defp order_by_queue_management(query, :FIFO) do
    order_by(query, [latest_connection: lc], asc: lc.established_at)
  end

  defp order_by_queue_management(query, :LIFO) do
    order_by(query, [d], desc_nulls_last: d.first_seen_at)
  end

  @doc """
  Resolve an update for the device's deployment
  """
  @spec resolve_update(Device.t()) :: UpdatePayload.t()
  def resolve_update(device, deployment_group \\ nil, opts \\ [])

  def resolve_update(%Device{status: :registered}, nil, _), do: %UpdatePayload{update_available: false}

  def resolve_update(%Device{deployment_id: nil}, nil, _), do: %UpdatePayload{update_available: false}

  def resolve_update(%Device{firmware_metadata: fw_meta} = device, nil, _) do
    Logger.metadata(device_id: device.id, source_firmware_uuid: Map.get(fw_meta, :uuid))
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(device)

    opts =
      if proxy_url = get_in(deployment_group.org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    resolve_update(device, deployment_group, opts)
  end

  def resolve_update(device, deployment_group, opts) do
    case verify_update_eligibility(device, deployment_group) do
      {:ok, _device} ->
        case Firmwares.get_delta_or_firmware(device, deployment_group) do
          {:ok, firmware_or_delta} ->
            {:ok, meta} = Firmwares.metadata_from_firmware(deployment_group.current_release.firmware)

            {:ok, url} = Firmwares.get_firmware_url(firmware_or_delta)

            firmware_url =
              if opts[:firmware_proxy_url] do
                opts[:firmware_proxy_url] <> "?firmware=#{Base.url_encode64(url, padding: false)}"
              else
                url
              end

            %UpdatePayload{
              update_available: true,
              firmware_url: firmware_url,
              firmware_meta: meta,
              deployment_group: deployment_group,
              deployment_id: deployment_group.id,
              size: firmware_or_delta.size,
              checksum: firmware_or_delta.checksum,
              partials_checksums: firmware_or_delta.partials_checksums
            }
        end

      {:error, :deployment_group_not_active, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :up_to_date, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :updates_blocked, _device} ->
        %UpdatePayload{update_available: false}
    end
  end

  @spec failure_threshold_met?(Device.t(), DeploymentGroup.t()) :: boolean()
  def failure_threshold_met?(%Device{} = device, %DeploymentGroup{} = deployment_group) do
    Enum.count(device.update_attempts) >= deployment_group.device_failure_threshold
  end

  @spec failure_rate_met?(Device.t(), DeploymentGroup.t()) :: boolean()
  def failure_rate_met?(%Device{} = device, %DeploymentGroup{} = deployment_group) do
    seconds_ago =
      Timex.shift(DateTime.utc_now(), seconds: -deployment_group.device_failure_rate_seconds)

    attempts =
      Enum.filter(device.update_attempts, fn attempt ->
        DateTime.before?(seconds_ago, attempt)
      end)

    Enum.count(attempts) >= deployment_group.device_failure_rate_amount
  end

  @doc """
  Devices that haven't been automatically blocked are not in the penalty window.
  Devices that have a time greater than now are in the penalty window.
  """
  @spec device_in_penalty_box?(device_or_device_info :: Device.t() | DeviceInfo.t(), now :: DateTime.t()) :: boolean()
  def device_in_penalty_box?(device_or_device_info, now \\ DateTime.utc_now())

  def device_in_penalty_box?(%DeviceInfo{device_updates_blocked_until: nil}, _now), do: false

  def device_in_penalty_box?(%Device{updates_blocked_until: nil}, _now), do: false

  def device_in_penalty_box?(%DeviceInfo{} = device_info, now) do
    DateTime.after?(device_info.device_updates_blocked_until, now)
  end

  def device_in_penalty_box?(%Device{} = device, now) do
    DateTime.after?(device.updates_blocked_until, now)
  end

  # A :device_managed device is not blocked — it is simply never pushed to, which
  # the orchestrator's available-devices query enforces. It still reaches here
  # when it asks for an update itself, and must pass.
  defp updates_blocked?(device, now) do
    device.update_mode == :off || device_in_penalty_box?(device, now)
  end

  def device_matches_deployment_group?(device, deployment_group) do
    device.firmware_metadata.uuid == deployment_group.current_release.firmware.uuid
  end

  def verify_update_eligibility(device, deployment_group, now \\ DateTime.utc_now()) do
    cond do
      not deployment_group.is_active ->
        {:error, :deployment_group_not_active, device}

      device_matches_deployment_group?(device, deployment_group) ->
        {:error, :up_to_date, device}

      updates_blocked?(device, now) ->
        FirmwareUpdates.clear_inflight_update(device)

        {:error, :updates_blocked, device}

      failure_rate_met?(device, deployment_group) ->
        {:ok, device} = put_device_in_penalty_box(device, deployment_group, :exceeded_failure_rate)

        {:error, :updates_blocked, device}

      failure_threshold_met?(device, deployment_group) ->
        {:ok, device} = put_device_in_penalty_box(device, deployment_group, :exceeded_failure_threshold)

        {:error, :updates_blocked, device}

      true ->
        {:ok, device}
    end
  end

  defp put_device_in_penalty_box(device, deployment_group, reason) do
    blocked_until =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(deployment_group.penalty_timeout_minutes * 60, :second)

    :ok = DeviceTemplates.audit_firmware_upgrade_blocked(deployment_group, device)
    _ = FirmwareUpdates.clear_inflight_update(device)

    device =
      Repo.preload(device, [:org, :product, :current_device_firmware, deployment_group: [current_release: :firmware]])

    Logger.info("Device #{device.identifier} put in penalty box until #{blocked_until}", %{
      identifier: device.identifier,
      org: device.org.name,
      product: device.product.name,
      platform: deployment_group.platform,
      current_firmware_version: device.current_device_firmware.firmware_metadata.version,
      upgrading_firmware_version: device.deployment_group.current_release.firmware.version,
      reason: reason
    })

    Devices.update_device(device, %{updates_blocked_until: blocked_until, update_attempts: []})
  end

  @spec update_attempted(DeviceInfo.t(), DateTime.t()) :: :ok | {:error, Changeset.t()}
  def update_attempted(device_info, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    Multi.new()
    |> Multi.update_all(
      :device,
      fn _ ->
        Device
        |> where(id: ^device_info.device_id)
        |> update(set: [update_attempts: fragment("update_attempts || ?::timestamp", ^now)])
      end,
      []
    )
    |> Multi.run(:audit_device, fn _, _ ->
      DeviceTemplates.audit_update_attempt(device_info)
    end)
    |> Repo.transact()
    |> case do
      {:ok, _} ->
        :ok

      err ->
        err
    end
  end

  @doc """
  Set a device's update mode.

  `enable_updates/2` and `disable_updates/2` remain as the two-state shortcuts
  the UI toggle and the bulk actions use; this is the general form, and the one
  a device uses when it asks to manage its own updates.

  Moving to `:automatic` re-evaluates the device against its deployment group
  straight away, so a device that opts back in does not wait for its next
  reconnect to be considered.
  """
  @spec set_update_mode(Device.t(), Device.update_mode(), User.t() | :device) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def set_update_mode(%Device{} = device, mode, actor) when mode in [:off, :automatic, :device_managed] do
    description =
      case actor do
        :device -> "Device #{device.identifier} set its update mode to #{mode}"
        user -> "User #{user.name} set the update mode for device #{device.identifier} to #{mode}"
      end

    params =
      if mode == :automatic do
        %{update_mode: mode, update_attempts: []}
      else
        %{update_mode: mode}
      end

    # The device itself is the audit actor when it sets its own mode, which is how
    # the log distinguishes a device opting in from a user changing it for them.
    audit_actor = if actor == :device, do: device, else: actor

    case Devices.update_device_with_audit(device, params, audit_actor, description) do
      {:ok, device} = result ->
        _ =
          if mode == :automatic and device.deployment_id do
            DeploymentOrchestratorEvents.device_updated(device)
          end

        result

      {:error, _, _, _} = result ->
        result
    end
  end

  @spec enable_updates(Device.t() | [Device.t()], User.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def enable_updates(%Device{} = device, user) do
    description = "User #{user.name} enabled updates for device #{device.identifier}"
    params = %{update_mode: :automatic, update_attempts: []}

    case Devices.update_device_with_audit(device, params, user, description) do
      {:ok, device} = result ->
        _ =
          if device.deployment_id do
            DeploymentOrchestratorEvents.device_updated(device)
          end

        result

      {:error, _, _, _} = result ->
        result
    end
  end

  @spec disable_updates(Device.t() | [Device.t()], User.t()) ::
          {:ok, Device.t()} | {:error, any(), any(), any()}
  def disable_updates(%Device{} = device, user) do
    description = "User #{user.name} disabled updates for device #{device.identifier}"
    params = %{update_mode: :off}
    Devices.update_device_with_audit(device, params, user, description)
  end

  def toggle_automatic_updates(device, user) do
    case device.update_mode do
      :off -> enable_updates(device, user)
      _ -> disable_updates(device, user)
    end
  end

  @doc """
  Release a device from the penalty box.

  Deliberately leaves `update_mode` alone. The penalty box is a separate
  mechanism — `updates_blocked?/2` ORs the two together — and clearing it used
  to re-enable updates an operator had turned off, which was never the intent of
  the button.
  """
  def clear_penalty_box(%Device{} = device, user) do
    description = "User #{user.name} removed device #{device.identifier} from the penalty box"
    params = %{updates_blocked_until: nil, update_attempts: []}
    Devices.update_device_with_audit(device, params, user, description)
  end

  def update_blocked_until(device, deployment) do
    blocked_until =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

    DeviceTemplates.audit_firmware_upgrade_blocked(deployment, device)

    Devices.update_device(device, %{updates_blocked_until: blocked_until})
  end
end
