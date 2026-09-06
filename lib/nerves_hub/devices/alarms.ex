defmodule NervesHub.Devices.Alarms do
  @moduledoc """
  Currently-raised device alarms, and the transitions that got them there.

  A health report carries the device's *complete current* alarm set, not
  events, so nothing tells the platform that an alarm was raised or cleared —
  `sync/3` derives both by diffing the report against what is already stored.
  Alarms present that were not stored are raises; alarms stored that the report
  no longer carries are resolves.

  Current state lives in PostgreSQL (`NervesHub.Devices.DeviceAlarm`), one row
  per raised alarm, because it has to be filterable alongside the rest of a
  device's state in one query. The transitions go to ClickHouse
  (`NervesHub.Devices.DeviceAlarmHistory`), where an append-only edge stream is
  cheap to keep and cheap to window over.

  A device that disconnects while alarming keeps its alarms: what a device was
  reporting when it stopped reporting is usually the interesting part, and
  whether it is still there is what the connection status is for. Product-wide
  alarm reads therefore include offline devices; narrow on connection status at
  the call site if that is not what is wanted.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceAlarm
  alias NervesHub.Devices.DeviceAlarmHistory
  alias NervesHub.Repo

  require Logger

  @elixir_prefix "Elixir."

  @doc """
  Record the device's current alarm set, raising and resolving as the diff
  against the stored set requires.

  `alarms` is the report's alarm map — `%{name => description}`. An empty map
  is meaningful: it resolves everything the device had raised.

  The diff and the writes happen in one transaction, so a device is never
  briefly seen with no alarms or a half-applied set — `current_alarms_count/1`
  and the index filters read this table live. Transition rows are buffered
  afterwards, outside the transaction, because the buffer is a cast and a
  ClickHouse hiccup is no reason to lose the PostgreSQL write.
  """
  @spec sync(DeviceInfo.t(), map(), DateTime.t()) :: :ok
  def sync(device_info, alarms, at \\ DateTime.utc_now())

  def sync(%DeviceInfo{} = device_info, alarms, %DateTime{} = at) when is_map(alarms) do
    current = normalize(alarms)
    names = Map.keys(current)

    Multi.new()
    |> Multi.all(:stored, from(a in DeviceAlarm, where: a.device_id == ^device_info.device_id, select: a.alarm))
    |> Multi.run(:upsert, fn repo, _ -> upsert(repo, device_info, current, at) end)
    |> Multi.run(:resolve, fn repo, _ -> resolve(repo, device_info.device_id, names) end)
    |> Repo.transact()
    |> case do
      {:ok, %{stored: stored}} ->
        record_transitions(device_info, current, stored, at)

      {:error, step, reason, _changes} ->
        Logger.warning("[Alarms] failed to sync alarms at #{inspect(step)}: #{inspect(reason)}")
        :ok
    end
  end

  def sync(%DeviceInfo{}, _not_a_map, _at), do: :ok

  @doc """
  Every distinct alarm currently raised anywhere in the product, sorted.

  Backs the alarm picker on the device index and the values the advanced query
  offers for the `alarm` field.
  """
  @spec get_current_alarm_types(pos_integer()) :: [String.t()]
  def get_current_alarm_types(product_id) do
    DeviceAlarm
    |> where(product_id: ^product_id)
    |> distinct(true)
    |> order_by([a], asc: a.alarm)
    |> select([a], a.alarm)
    |> Repo.all()
  end

  @doc """
  How many of the product's devices have at least one alarm raised.
  """
  @spec current_alarms_count(pos_integer()) :: non_neg_integer()
  def current_alarms_count(product_id) do
    DeviceAlarm
    |> where(product_id: ^product_id)
    |> distinct(true)
    |> select([a], a.device_id)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  @doc """
  The device's raised alarms as `[{alarm, description}]`, oldest first, or
  `nil` when it has none — the device details page distinguishes "no alarms"
  from "alarms" rather than rendering an empty list.
  """
  @spec current_alarms_for_device(Device.t() | pos_integer()) :: [{String.t(), String.t() | nil}] | nil
  def current_alarms_for_device(%Device{id: device_id}), do: current_alarms_for_device(device_id)

  def current_alarms_for_device(device_id) when is_integer(device_id) do
    DeviceAlarm
    |> where(device_id: ^device_id)
    |> order_by([a], asc: a.raised_at, asc: a.alarm)
    |> select([a], {a.alarm, a.description})
    |> Repo.all()
    |> case do
      [] -> nil
      alarms -> alarms
    end
  end

  # ------------------------------------------------------------------ writes

  defp upsert(_repo, _device_info, current, _at) when map_size(current) == 0, do: {:ok, 0}

  defp upsert(repo, device_info, current, at) do
    entries =
      for {alarm, description} <- current do
        %{
          device_id: device_info.device_id,
          product_id: device_info.product_id,
          alarm: alarm,
          description: description,
          raised_at: at
        }
      end

    # `:description` alone, deliberately. Every report re-asserts the whole
    # alarm set, so replacing `raised_at` here would make it mean "last
    # reported" rather than "raised at" — which is the only reason the column
    # exists.
    {count, _} =
      repo.insert_all(DeviceAlarm, entries,
        on_conflict: {:replace, [:description]},
        conflict_target: [:device_id, :alarm]
      )

    {:ok, count}
  end

  defp resolve(repo, device_id, []) do
    {count, _} = repo.delete_all(from(a in DeviceAlarm, where: a.device_id == ^device_id))
    {:ok, count}
  end

  defp resolve(repo, device_id, names) do
    {count, _} =
      repo.delete_all(from(a in DeviceAlarm, where: a.device_id == ^device_id and a.alarm not in ^names))

    {:ok, count}
  end

  defp record_transitions(device_info, current, stored, at) do
    stored = MapSet.new(stored)
    names = current |> Map.keys() |> MapSet.new()

    for alarm <- MapSet.difference(names, stored) do
      write_history(device_info, alarm, "raised", current[alarm], at)
    end

    for alarm <- MapSet.difference(stored, names) do
      write_history(device_info, alarm, "resolved", nil, at)
    end

    :ok
  end

  # Gated explicitly rather than relying on a cast to a missing name quietly
  # succeeding, the same way `NervesHub.Devices.Metrics` gates its writes: a
  # deployment without analytics is a decision this code made.
  defp write_history(device_info, alarm, event, description, at) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Buffer.insert(
        DeviceAlarmHistory,
        DeviceAlarmHistory.changeset(%{
          timestamp: at,
          org_id: device_info.org_id,
          product_id: device_info.product_id,
          device_id: device_info.device_id,
          alarm: alarm,
          event: event,
          description: description || ""
        })
      )
    end

    :ok
  end

  # Alarm names arrive from the Erlang alarm handler as `Elixir.Some.Module`.
  # Stripped once here rather than at every read, so what is stored is what is
  # displayed and what a filter matches. Non-string descriptions are coerced:
  # the value is whatever the device chose to send.
  defp normalize(alarms) do
    for {alarm, description} <- alarms,
        is_binary(alarm),
        name = String.trim_leading(alarm, @elixir_prefix),
        name != "",
        into: %{} do
      {name, describe(description)}
    end
  end

  defp describe(description) when is_binary(description), do: description
  defp describe(nil), do: nil
  defp describe(description), do: inspect(description)
end
