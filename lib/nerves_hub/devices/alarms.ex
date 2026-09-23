defmodule NervesHub.Devices.Alarms do
  @moduledoc """
  Currently-raised device alarms, and the transitions that got them there.

  Alarms arrive two ways, and both end here.

    * **As a set.** A health report, and the `alarms` extension's snapshot,
      carry the device's *complete current* alarm set. Nothing in a set says
      what was raised or cleared, so `sync/3` derives both by diffing it
      against what is already stored: alarms present that were not stored are
      raises, alarms stored that the set no longer carries are resolves.
    * **As events.** The `alarms` extension sends each raise and clear as it
      happens, and `raise_alarm/4` and `clear_alarm/3` apply them one at a
      time. See `NervesHub.Extensions.Alarms` for why a device still sends a
      set as well.

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
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Repo

  require Logger

  @elixir_prefix "Elixir."

  @typedoc "One raised alarm in a set: name, description, and when it was raised (`nil` for now)."
  @type entry() :: {String.t(), term(), DateTime.t() | nil}

  # `device_alarms.alarm` is a varchar(255). A longer name would fail the whole
  # write, so it is dropped on the way in like any other unusable name.
  @max_name_length 255

  @doc """
  Record the device's current alarm set, raising and resolving as the diff
  against the stored set requires.

  `alarms` is either a health report's alarm map, `%{name => description}`, or
  a list of `{name, description, raised_at}`, which is the `alarms`
  extension's snapshot once it has been parsed. `raised_at` is when the device
  says the alarm was raised, and `nil` means `at`; it only matters for an alarm
  not already stored, since an alarm already raised keeps the start of its
  episode. An empty map or list is meaningful: it resolves everything the
  device had raised.

  The diff and the writes happen in one transaction, so a device is never
  briefly seen with no alarms or a half-applied set — `current_alarms_count/1`
  and the index filters read this table live. Transition rows are buffered
  afterwards, outside the transaction, because the buffer is a cast and a
  ClickHouse hiccup is no reason to lose the PostgreSQL write.
  """
  @spec sync(DeviceInfo.t(), map() | [entry()], DateTime.t()) :: :ok
  def sync(device_info, alarms, at \\ DateTime.utc_now())

  def sync(%DeviceInfo{} = device_info, alarms, %DateTime{} = at) when is_map(alarms) do
    sync(device_info, for({alarm, description} <- alarms, do: {alarm, description, nil}), at)
  end

  def sync(%DeviceInfo{} = device_info, alarms, %DateTime{} = at) when is_list(alarms) do
    current = normalize(alarms, at)
    names = Map.keys(current)

    Multi.new()
    |> Multi.all(:stored, from(a in DeviceAlarm, where: a.device_id == ^device_info.device_id, select: a.alarm))
    |> Multi.run(:upsert, fn repo, _ -> upsert(repo, device_info, current) end)
    |> Multi.run(:resolve, fn repo, _ -> resolve(repo, device_info.device_id, names) end)
    |> Repo.transact()
    |> case do
      {:ok, %{stored: stored}} ->
        :ok = record_transitions(device_info, current, stored, at)

      {:error, step, reason, _changes} ->
        Logger.warning("[Alarms] failed to sync alarms at #{inspect(step)}: #{inspect(reason)}")
        :ok
    end
  end

  def sync(%DeviceInfo{}, _not_a_map_or_list, _at), do: :ok

  @doc """
  Record one alarm the device has just raised.

  An alarm already raised is not raised again: `raised_at` keeps the start of
  the episode, no second `raised` edge is recorded, and only the description is
  brought up to date. A device repeating itself is therefore harmless, which is
  what lets it re-send an event it is not sure arrived.

  `at` is when the alarm was raised: the device's own time where it gave a
  believable one, otherwise when the platform heard about it. It becomes both
  `raised_at` and the time of the `raised` edge in the history.

  A name that is not usable (see `sync/3`) is ignored.
  """
  @spec raise_alarm(DeviceInfo.t(), String.t(), term(), DateTime.t()) :: :ok
  def raise_alarm(device_info, alarm, description, at \\ DateTime.utc_now())

  def raise_alarm(%DeviceInfo{} = device_info, alarm, description, %DateTime{} = at) do
    case normalize_name(alarm) do
      {:ok, name} -> insert_or_describe(device_info, name, describe(description), at)
      :error -> :ok
    end
  end

  @doc """
  Record that the device has cleared one alarm.

  Clearing an alarm that is not raised does nothing and records nothing, for
  the same reason `raise_alarm/4` tolerates a repeat. `at` is when it cleared,
  on the same terms as `raise_alarm/4`'s.
  """
  @spec clear_alarm(DeviceInfo.t(), String.t(), DateTime.t()) :: :ok
  def clear_alarm(device_info, alarm, at \\ DateTime.utc_now())

  def clear_alarm(%DeviceInfo{} = device_info, alarm, %DateTime{} = at) do
    with {:ok, name} <- normalize_name(alarm),
         {1, _} <-
           Repo.delete_all(from(a in DeviceAlarm, where: a.device_id == ^device_info.device_id and a.alarm == ^name)) do
      :ok = write_history(device_info, name, "resolved", nil, at)
      broadcast(device_info)
    else
      _ -> :ok
    end
  end

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

  defp upsert(_repo, _device_info, current) when map_size(current) == 0, do: {:ok, 0}

  defp upsert(repo, device_info, current) do
    entries =
      for {alarm, {description, raised_at}} <- current do
        %{
          device_id: device_info.device_id,
          product_id: device_info.product_id,
          alarm: alarm,
          description: description,
          raised_at: raised_at
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

  # Insert first and let the unique index say whether this is a new episode.
  # Only when it is not does the description get a look, and only a description
  # that actually changed is worth telling an open page about.
  defp insert_or_describe(device_info, name, description, at) do
    entry = %{
      device_id: device_info.device_id,
      product_id: device_info.product_id,
      alarm: name,
      description: description,
      raised_at: at
    }

    case Repo.insert_all(DeviceAlarm, [entry], on_conflict: :nothing, conflict_target: [:device_id, :alarm]) do
      {1, _} ->
        :ok = write_history(device_info, name, "raised", description, at)
        broadcast(device_info)

      {0, _} ->
        described =
          from(a in DeviceAlarm,
            where: a.device_id == ^device_info.device_id and a.alarm == ^name,
            where: fragment("? IS DISTINCT FROM ?", a.description, ^description)
          )

        case Repo.update_all(described, set: [description: description]) do
          {0, _} -> :ok
          {_count, _} -> broadcast(device_info)
        end
    end
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

    raised = MapSet.difference(names, stored)
    resolved = MapSet.difference(stored, names)

    for alarm <- raised do
      {description, raised_at} = current[alarm]
      write_history(device_info, alarm, "raised", description, raised_at)
    end

    for alarm <- resolved do
      write_history(device_info, alarm, "resolved", nil, at)
    end

    if Enum.empty?(raised) and Enum.empty?(resolved), do: :ok, else: broadcast(device_info)
  end

  # Tells an open device page to re-read the alarm list. Sent only when the list
  # moved, so a set that re-asserts what is already stored costs nothing.
  defp broadcast(device_info) do
    ExtensionsPubSub.broadcast_report(device_info.device_id, "alarms:updated", %{})
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
  defp normalize(alarms, at) do
    for {alarm, description, raised_at} <- alarms,
        {:ok, name} <- [normalize_name(alarm)],
        into: %{} do
      {name, {describe(description), raised_at || at}}
    end
  end

  defp normalize_name(alarm) when is_binary(alarm) do
    name = String.trim_leading(alarm, @elixir_prefix)

    if name != "" and String.length(name) <= @max_name_length, do: {:ok, name}, else: :error
  end

  defp normalize_name(_alarm), do: :error

  defp describe(description) when is_binary(description), do: description
  defp describe(nil), do: nil
  defp describe(description), do: inspect(description)
end
