defmodule NervesHub.Devices.UpdateHistory do
  @moduledoc """
  The record of how firmware update attempts ended.

  A device's update lives in `inflight_updates` while it is running and is
  deleted the moment it reaches an outcome, so nothing in PostgreSQL remembers
  that an update was ever attempted, let alone that it failed. The audit log
  carries a sentence per event, which is readable one device at a time and
  useless in aggregate — a product with a badly behaved fleet fills pages of it
  without ever saying how many updates failed this week.

  This module closes that gap, writing two things for every attempt that ends:

    * a row in `device_update_history` (ClickHouse, via
      `NervesHub.Analytics.Buffer`) — the history itself, which the Insights
      graph reads; and
    * the device's `consecutive_failed_updates` counter (PostgreSQL) — the
      current state, which the penalty box list reads.

  Two stores for one fact, as with `device_health` / `device_health_history` and
  `device_alarms` / `device_alarm_history`. The counter is not derived from the
  history because the history is analytics: it is eventually consistent, it is
  only written where `:analytics_enabled` is set, and its buffer sheds rows
  rather than block. "How many times in a row has this device failed" is an
  operational answer that has to be exact and has to exist everywhere.

  ## Statuses

  An attempt ends exactly one of six ways:

    * `:succeeded` — the device rejoined running the firmware it was sent.
    * `:failed` — the device reported an error while updating.
    * `:ignored` — the device declined the update outright.
    * `:rescheduled` — the device asked for the update to come back later.
    * `:expired` — the update stopped making progress and timed out.
    * `:abandoned` — the device rejoined still running its old firmware, with
      nothing to say about why. This is the quiet one, and on a fleet that is
      failing to update it is usually the most common: no report is sent, the
      device simply comes back as it left.

  All six are recorded. `:rescheduled` is the only one that is **not** counted
  as a failure: a device that asks for the update later is negotiating, not
  failing, and counting it would libel every product whose devices defer
  updates while they are busy. The other four all mean the device did not take
  the firmware it was sent, so `failure_statuses/0` covers them and the counter
  moves on each.

  `:expired` and `:abandoned` are worked out by `NervesHub.FirmwareUpdates`
  rather than reported, so it records them only for an update this server sent,
  which is one with a firmware. A device that reports progress on an update the
  server already stopped tracking gets an inflight update with no firmware, and
  that one ends unrecorded unless the device comes back running new firmware.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Integrations
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Payloads

  @typedoc """
  An outcome that means the device did not end up running the firmware it was
  sent. See the module documentation for why `:rescheduled` is not one.
  """
  @type failure_status :: :failed | :ignored | :expired | :abandoned

  @type status :: :succeeded | :rescheduled | failure_status()

  @typedoc """
  What `record/3` needs of a device: enough to find its row and to scope the
  history entry.

  A `Device` struct satisfies it, and so do the partial device
  `NervesHub.FirmwareUpdates` carries and the plain map its expiry sweep builds
  out of a `DELETE ... RETURNING`.
  """
  @type device :: %{
          required(:id) => pos_integer(),
          required(:org_id) => pos_integer(),
          required(:product_id) => pos_integer(),
          optional(any()) => any()
        }

  @statuses [:succeeded, :failed, :ignored, :rescheduled, :expired, :abandoned]
  @failure_statuses [:failed, :ignored, :expired, :abandoned]

  # Device reasons are free text off the wire. `DeviceTemplates` truncates them
  # to the same length before they reach an audit entry.
  @reason_max_length 200

  @doc """
  Every status an update attempt can end with.
  """
  @spec statuses() :: [status(), ...]
  def statuses(), do: @statuses

  @doc """
  The statuses that count as the device having failed to take its firmware.

  `:rescheduled` is not one of them — see the module documentation.
  """
  @spec failure_statuses() :: [failure_status(), ...]
  def failure_statuses(), do: @failure_statuses

  @doc """
  Records how one firmware update attempt ended.

  Writes the history row (ClickHouse, when analytics is enabled) and moves the
  device's failure counter (PostgreSQL, always) — see the module documentation
  for why both. Callers pass whatever they hold; `device` needs only `:id`,
  `:org_id` and `:product_id`, which is what the partial device
  `NervesHub.FirmwareUpdates` works with carries.

  ## Options

    * `:deployment_id` - the deployment group that asked for the update, if any.
    * `:source_firmware_uuid` - the firmware the device was running.
    * `:target_firmware_uuid` - the firmware it was being moved to.
    * `:reason` - what the device said, where it said anything.
    * `:timestamp` - when the attempt ended, defaulting to now.
    * `:started_at` - when the update was sent, so the row can say how long
      it took. Left out, the duration is recorded as unknown (0).

  Raises the `device.firmware_update.finished` event (`NervesHub.Integrations`).

  Runs in the caller's transaction when there is one, so a rolled back outcome
  takes its counter movement, and its event, with it.
  """
  @spec record(device(), status(), keyword()) :: :ok
  def record(device, status, opts \\ []) when status in @statuses do
    timestamp =
      opts
      |> Keyword.get_lazy(:timestamp, &DateTime.utc_now/0)
      # `DateTime64(6)` is `:utc_datetime_usec` to Ecto, which refuses anything
      # coarser than microseconds. Adding zero of them relabels the precision
      # without moving the instant. Worth doing rather than trusting callers:
      # a rejected row fails the whole buffer batch, so a second-precision
      # timestamp here would take unrelated rows down with it.
      |> DateTime.add(0, :microsecond)

    _ = move_counter(device, status, timestamp)

    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Buffer.insert(
        DeviceUpdateHistory,
        DeviceUpdateHistory.changeset(%{
          timestamp: timestamp,
          org_id: device.org_id,
          product_id: device.product_id,
          device_id: device.id,
          deployment_id: opts[:deployment_id] || 0,
          status: Atom.to_string(status),
          source_firmware_uuid: uuid(opts[:source_firmware_uuid]),
          target_firmware_uuid: uuid(opts[:target_firmware_uuid]),
          reason: reason(opts[:reason]),
          duration_seconds: duration_seconds(opts[:started_at], timestamp)
        })
      )
    end

    # Every outcome passes through here, which makes this the one place an
    # integration can hear about all of them.
    Integrations.dispatch(device.product_id, "device.firmware_update.finished", fn ->
      Payloads.firmware_update_finished(
        device,
        status,
        Keyword.put(opts, :reason, opts[:reason] && reason(opts[:reason]))
      )
    end)
  end

  # A success ends the run of failures, so the count goes back to zero and both
  # timestamps with it — a device that has taken firmware is neither "failing
  # since" nor "last failed at" anything. A reschedule moves none of them.
  defp move_counter(device, :succeeded, _timestamp) do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [consecutive_failed_updates: 0, first_update_failure_at: nil, last_update_failure_at: nil])
  end

  defp move_counter(device, status, timestamp) when status in @failure_statuses do
    at = DateTime.truncate(timestamp, :second)

    from(d in Device,
      where: d.id == ^device.id,
      update: [
        inc: [consecutive_failed_updates: 1],
        set: [
          last_update_failure_at: ^at,
          # The run began at its first failure, so the COALESCE leaves this
          # alone once set. Done in the statement rather than by reading the
          # row back first, so concurrent failures cannot race the run's start.
          first_update_failure_at: fragment("COALESCE(?, ?)", d.first_update_failure_at, type(^at, :utc_datetime))
        ]
      ]
    )
    |> Repo.update_all([])
  end

  defp move_counter(_device, :rescheduled, _timestamp), do: {0, nil}

  # Whole seconds, and never negative: a clock that moved between the update
  # being sent and the attempt ending must not wrap a UInt32.
  defp duration_seconds(nil, _ended_at), do: 0

  defp duration_seconds(%NaiveDateTime{} = started_at, ended_at),
    do: duration_seconds(DateTime.from_naive!(started_at, "Etc/UTC"), ended_at)

  defp duration_seconds(%DateTime{} = started_at, ended_at), do: max(DateTime.diff(ended_at, started_at), 0)

  defp uuid(nil), do: ""
  defp uuid(uuid) when is_binary(uuid), do: uuid

  defp reason(nil), do: ""
  defp reason(reason) when is_binary(reason), do: String.slice(reason, 0, @reason_max_length)
  # A device is free to put anything in the reason field, including something
  # that is not a string at all, and a recorded outcome must not depend on it.
  defp reason(reason), do: reason |> inspect() |> String.slice(0, @reason_max_length)

  @doc """
  How many attempts to move one of the product's devices to `firmware_uuid`
  have failed since `since`, for the firmware's page.

  Counts attempts, not devices: a device that failed twice counts twice, the
  same as the Insights graph does.
  """
  @spec failed_attempts_count(pos_integer(), pos_integer(), String.t(), DateTime.t()) :: non_neg_integer()
  def failed_attempts_count(org_id, product_id, firmware_uuid, %DateTime{} = since) do
    failure_names = Enum.map(@failure_statuses, &Atom.to_string/1)

    query =
      from h in DeviceUpdateHistory,
        where: h.org_id == ^org_id,
        where: h.product_id == ^product_id,
        where: h.target_firmware_uuid == ^firmware_uuid,
        where: h.status in ^failure_names,
        where: h.timestamp >= ^since,
        select: fragment("count()")

    AnalyticsRepo.one(query)
  end

  @max_attempts_page_size 100

  @typedoc """
  One finished attempt as `device_attempts/3` returns it, with its firmware
  and deployment group looked up. A deployment group this product no longer
  has comes back as `nil`; see `t:firmware_ref/0` for a missing firmware.
  """
  @type attempt :: %{
          timestamp: DateTime.t(),
          status: status(),
          reason: String.t() | nil,
          source: firmware_ref() | nil,
          target: firmware_ref() | nil,
          deployment_group: %{id: pos_integer(), name: String.t()} | nil
        }

  @typedoc """
  A firmware an attempt names. `version` is nil when this product has no
  firmware with that UUID, and `available?` is false when it has one but it
  was deleted, so there is no firmware page to link to.
  """
  @type firmware_ref :: %{uuid: String.t(), version: String.t() | nil, available?: boolean()}

  @type page :: %{
          current_page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }

  @doc """
  One page of a device's finished update attempts, newest first, for the
  device page's Update attempts view.

  Reads ClickHouse, so it is empty where `:analytics_enabled` is not set, and
  an attempt that has just ended may take a moment to appear.

  `page` and `page_size` come from the page's URL, so they are clamped: the
  page to 1 or more, and the page size to between 1 and #{@max_attempts_page_size}.
  """
  @spec device_attempts(device(), integer(), integer()) :: {[attempt()], page()}
  def device_attempts(device, page, page_size) do
    page = max(page, 1)
    page_size = page_size |> max(1) |> min(@max_attempts_page_size)

    if Application.get_env(:nerves_hub, :analytics_enabled) do
      attempts_page(device, page, page_size)
    else
      {[], %{current_page: 1, page_size: page_size, total_count: 0, total_pages: 0}}
    end
  end

  defp attempts_page(device, page, page_size) do
    base =
      from h in DeviceUpdateHistory,
        where: h.org_id == ^device.org_id,
        where: h.product_id == ^device.product_id,
        where: h.device_id == ^device.id

    total_count = AnalyticsRepo.one(from(h in base, select: fragment("count()"))) || 0

    rows =
      from(h in base,
        order_by: [desc: h.timestamp],
        limit: ^page_size,
        offset: ^((page - 1) * page_size),
        select: %{
          timestamp: h.timestamp,
          status: h.status,
          reason: h.reason,
          source_firmware_uuid: h.source_firmware_uuid,
          target_firmware_uuid: h.target_firmware_uuid,
          deployment_id: h.deployment_id
        }
      )
      |> AnalyticsRepo.all()

    {resolve(rows, device.product_id),
     %{
       current_page: page,
       page_size: page_size,
       total_count: total_count,
       total_pages: div(total_count + page_size - 1, page_size)
     }}
  end

  defp resolve(rows, product_id) do
    uuids =
      rows
      |> Enum.flat_map(&[&1.source_firmware_uuid, &1.target_firmware_uuid])
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    versions =
      from(f in Firmware,
        where: f.product_id == ^product_id,
        where: f.uuid in ^uuids,
        select: {f.uuid, %{version: f.version, available?: is_nil(f.deleted_at)}}
      )
      |> Repo.all()
      |> Map.new()

    deployment_ids = rows |> Enum.map(& &1.deployment_id) |> Enum.reject(&(&1 == 0)) |> Enum.uniq()

    groups =
      from(d in DeploymentGroup,
        where: d.product_id == ^product_id,
        where: d.id in ^deployment_ids,
        select: {d.id, %{id: d.id, name: d.name}}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(rows, fn row ->
      %{
        timestamp: row.timestamp,
        status: String.to_existing_atom(row.status),
        reason: if(row.reason != "", do: row.reason),
        source: firmware(row.source_firmware_uuid, versions),
        target: firmware(row.target_firmware_uuid, versions),
        deployment_group: Map.get(groups, row.deployment_id)
      }
    end)
  end

  defp firmware("", _versions), do: nil

  defp firmware(uuid, versions) do
    case Map.fetch(versions, uuid) do
      {:ok, found} -> Map.put(found, :uuid, uuid)
      :error -> %{uuid: uuid, version: nil, available?: false}
    end
  end
end
