defmodule NervesHub.Devices.Components do
  @moduledoc """
  What each device is connected to, from its `components` snapshots.

  A device sends its whole component set, never single changes (see
  docs/components.md for why). `sync_snapshot/3` compares the set with what is
  stored, writes only the rows that changed, and records each change as
  history. A snapshot that changes nothing costs one read.

  Current components live in PostgreSQL (`NervesHub.Devices.DeviceComponent`),
  where the device page and the product's Components page read them. Changes go
  to ClickHouse (`NervesHub.Devices.DeviceComponentHistory`), as alarm
  transitions do, and are skipped where analytics are off.

  A component is missing when the device can't reach it or stops listing it.
  Neither deletes it: only `forget/3` does, because a sensor that dropped off
  its gateway is the one somebody is looking for.

  Version 0.2.0 of the extension adds what a component measures and what
  state it is in. `record_readings/2` keeps each component's latest readings
  on its row and every reading in ClickHouse
  (`NervesHub.Devices.DeviceComponentReading`). `record_state/3` keeps the
  current state on the row and each change in the component's history. A
  snapshot may carry state too, which replaces what is stored. Neither
  changes whether a component is working or missing.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceComponent
  alias NervesHub.Devices.DeviceComponentHistory
  alias NervesHub.Devices.DeviceComponentReading
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  require Logger

  @max_components 500
  @max_string_length 255
  @namespace_pattern ~r/\A[a-z][a-z0-9_]{0,31}\z/

  # Version 0.2.0: reading and state names, and how much of either is kept.
  @name_pattern ~r/\A[a-z][a-z0-9_]{0,63}\z/
  @max_states 8
  @max_state_value_length 64
  @max_reports_per_message 60
  @max_readings 20
  @max_reading_skew_seconds 24 * 60 * 60

  # The same window `NervesHub.Extensions.Alarms` believes a device's clock in.
  @max_future_skew_seconds 60 * 60
  @max_age_seconds 72 * 60 * 60

  @required ~w(namespace vendor model serial)
  @optional ~w(name vendor_name model_name hardware_revision firmware_version address)

  # Written on every upsert. `first_seen_at` and `inserted_at` are left alone,
  # since they say when the component was first seen, not last.
  @replaced [
    :vendor,
    :model,
    :name,
    :vendor_name,
    :model_name,
    :hardware_revision,
    :firmware_version,
    :address,
    :reachable,
    :listed,
    :last_seen_at,
    :missing_since,
    :state,
    :updated_at
  ]

  @typedoc """
  One component from a snapshot once `parse/2` has read it. `last_seen_at` is
  `nil` where the device gave no believable time.
  """
  @type entry() :: %{
          namespace: String.t(),
          vendor: String.t(),
          model: String.t(),
          serial: String.t(),
          name: String.t() | nil,
          vendor_name: String.t() | nil,
          model_name: String.t() | nil,
          hardware_revision: String.t() | nil,
          firmware_version: String.t() | nil,
          address: String.t() | nil,
          reachable: boolean(),
          last_seen_at: DateTime.t() | nil,
          state: %{String.t() => String.t()} | nil
        }

  @type rejection() ::
          :not_a_list | :too_many | :malformed_entry | :bad_namespace | :too_long | :duplicate | :bad_state

  @doc """
  Reads a snapshot's `components` list, or says why it is rejected.

  All or nothing, as docs/components.md describes: the set replaces what is
  stored, so an entry that can't be read would otherwise count as a component
  the device no longer has. Fields the contract doesn't name are ignored.
  """
  @spec parse(term(), DateTime.t()) :: {:ok, [entry()]} | {:error, rejection()}
  def parse(components, now \\ DateTime.utc_now())

  def parse(components, _now) when is_list(components) and length(components) > @max_components, do: {:error, :too_many}

  def parse(components, now) when is_list(components) do
    components
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn component, {:ok, acc, seen} ->
      with {:ok, entry} <- parse_entry(component, now),
           key = {entry.namespace, entry.serial},
           false <- MapSet.member?(seen, key) do
        {:cont, {:ok, [entry | acc], MapSet.put(seen, key)}}
      else
        true -> {:halt, {:error, :duplicate}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries, _seen} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  def parse(_components, _now), do: {:error, :not_a_list}

  defp parse_entry(component, now) when is_map(component) do
    with {:ok, required} <- strings(component, @required, required: true),
         {:ok, optional} <- strings(component, @optional, required: false),
         :ok <- check_namespace(required["namespace"]),
         {:ok, reachable} <- reachable(component["reachable"]),
         {:ok, state} <- snapshot_state(component["state"]) do
      entry =
        Map.merge(required, optional)
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
        |> Map.put(:reachable, reachable)
        |> Map.put(:last_seen_at, device_time(component["last_seen_at"], now))
        |> Map.put(:state, state)

      {:ok, entry}
    end
  end

  defp parse_entry(_component, _now), do: {:error, :malformed_entry}

  defp strings(component, keys, opts) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case Map.get(component, key) do
        nil when opts == [required: false] -> {:cont, {:ok, Map.put(acc, key, nil)}}
        value when is_binary(value) and value != "" -> check_length(key, value, acc)
        _missing_or_not_a_string -> {:halt, {:error, :malformed_entry}}
      end
    end)
  end

  # Counted in code points, as PostgreSQL counts a varchar, and refused when not
  # valid UTF-8, which PostgreSQL can't store at all.
  defp check_length(key, value, acc) do
    if String.valid?(value) and length(String.to_charlist(value)) <= @max_string_length,
      do: {:cont, {:ok, Map.put(acc, key, value)}},
      else: {:halt, {:error, :too_long}}
  end

  defp check_namespace(namespace) do
    if Regex.match?(@namespace_pattern, namespace), do: :ok, else: {:error, :bad_namespace}
  end

  # `nil` when the entry says nothing about state, which leaves what is stored.
  defp snapshot_state(nil), do: {:ok, nil}

  defp snapshot_state(state) when is_map(state) and map_size(state) <= @max_states do
    if Enum.all?(state, fn {name, value} -> state_name?(name) and state_value?(value) end),
      do: {:ok, state},
      else: {:error, :bad_state}
  end

  defp snapshot_state(_state), do: {:error, :bad_state}

  defp state_name?(name), do: is_binary(name) and Regex.match?(@name_pattern, name)

  defp state_value?(value),
    do: is_binary(value) and value != "" and String.valid?(value) and String.length(value) <= @max_state_value_length

  defp reachable(nil), do: {:ok, true}
  defp reachable(reachable) when is_boolean(reachable), do: {:ok, reachable}
  defp reachable(_reachable), do: {:error, :malformed_entry}

  # A time is used only where it is believable, as `NervesHub.Extensions.Alarms`
  # does: a clock that hasn't caught up with NTP can say 1970.
  defp device_time(timestamp, now) when is_binary(timestamp) do
    with {:ok, parsed, _offset} <- DateTime.from_iso8601(timestamp),
         ahead = DateTime.diff(parsed, now, :second),
         true <- ahead <= @max_future_skew_seconds and -ahead <= @max_age_seconds do
      parsed
    else
      _ -> nil
    end
  end

  defp device_time(_absent, _now), do: nil

  @doc """
  Records a device's snapshot: `entries` is everything it has now.

  New components are inserted, changed ones updated, and stored ones the
  snapshot leaves out are marked unlisted. The comparison and the writes are
  one transaction, so a page never reads half a snapshot. History is buffered
  after the commit, outside it, so a ClickHouse hiccup can't lose the
  PostgreSQL write, and an open device page is told only when something
  changed.
  """
  @spec sync_snapshot(DeviceInfo.t(), [entry()], DateTime.t()) :: :ok
  def sync_snapshot(%DeviceInfo{} = device_info, entries, %DateTime{} = now \\ DateTime.utc_now())
      when is_list(entries) do
    now = usec(now)

    Repo.transact(fn ->
      stored =
        DeviceComponent
        |> where(device_id: ^device_info.device_id)
        |> Repo.all()
        |> Map.new(&{{&1.namespace, &1.serial}, &1})

      {rows, events} = plan(device_info, entries, stored, now)
      {unlisted, unlisted_events} = unlisted(entries, stored, now)

      :ok = upsert(rows)
      :ok = mark_unlisted(unlisted, now)

      {:ok, events ++ unlisted_events}
    end)
    |> case do
      {:ok, []} ->
        :ok

      {:ok, events} ->
        :ok = write_history(device_info, events)
        broadcast(device_info.device_id)

      {:error, reason} ->
        Logger.warning("[Components] failed to sync device #{device_info.device_id}: #{inspect(reason)}")
        :ok
    end
  end

  # The rows to write and the history to record. A row only goes out when
  # something in it differs from what is stored: an unchanged snapshot writes
  # nothing.
  defp plan(device_info, entries, stored, now) do
    Enum.reduce(entries, {[], []}, fn entry, {rows, events} ->
      previous = Map.get(stored, {entry.namespace, entry.serial})
      row = row(device_info, entry, previous, now)

      if previous && unchanged?(row, previous) do
        {rows, events}
      else
        {[row | rows], changes(entry, previous, now) ++ events}
      end
    end)
  end

  defp row(device_info, entry, previous, now) do
    missing_since =
      cond do
        entry.reachable -> nil
        previous && previous.missing_since -> previous.missing_since
        true -> now
      end

    %{
      device_id: device_info.device_id,
      product_id: device_info.product_id,
      namespace: entry.namespace,
      vendor: entry.vendor,
      model: entry.model,
      serial: entry.serial,
      name: entry.name,
      vendor_name: entry.vendor_name,
      model_name: entry.model_name,
      hardware_revision: entry.hardware_revision,
      firmware_version: entry.firmware_version,
      address: entry.address,
      reachable: entry.reachable,
      listed: true,
      last_seen_at: last_seen_at(entry, previous, now),
      first_seen_at: (previous && previous.first_seen_at) || now,
      missing_since: missing_since,
      state: stored_state(entry.state, previous, now),
      inserted_at: now,
      updated_at: now
    }
  end

  # A snapshot's state replaces what is stored, keeping when each value it
  # repeats was set. One that says nothing about state leaves it alone.
  #
  # A snapshot carries no time for its state, so a value it sets is stamped
  # with the platform's clock and marked as coming from a snapshot. A change
  # is stamped with the device's clock, and the two can't be compared.
  defp stored_state(nil, previous, _now), do: (previous && previous.state) || %{}

  defp stored_state(state, previous, now) do
    stored = (previous && previous.state) || %{}

    Map.new(state, fn {name, value} ->
      case stored do
        %{^name => %{"value" => ^value} = kept} -> {name, kept}
        _ -> {name, %{"value" => value, "since" => DateTime.to_iso8601(now), "detail" => nil, "snapshot" => true}}
      end
    end)
  end

  # The device's time where it gave a believable one, and otherwise the last
  # one it gave. Never the arrival time: that would change every row on every
  # snapshot, and an unchanged snapshot is meant to write nothing. The web UI
  # falls back to when the device itself was last seen.
  defp last_seen_at(%{last_seen_at: %DateTime{} = at}, _previous, _now), do: usec(at)
  defp last_seen_at(_entry, %DeviceComponent{last_seen_at: at}, _now), do: at
  defp last_seen_at(_entry, nil, _now), do: nil

  defp unchanged?(row, previous) do
    Enum.all?(@replaced -- [:updated_at], fn field -> Map.fetch!(row, field) == Map.fetch!(previous, field) end)
  end

  defp changes(entry, nil, now) do
    appeared = event(entry, "appeared", "", now)
    status = if entry.reachable, do: [appeared], else: [appeared, event(entry, "missing", "unreachable", now)]
    status ++ state_changes(entry, %{}, now)
  end

  defp changes(entry, previous, now) do
    was_working? = DeviceComponent.status(previous) == :working

    status =
      cond do
        was_working? and not entry.reachable -> [event(entry, "missing", "unreachable", now)]
        not was_working? and entry.reachable -> [event(entry, "returned", "", now)]
        true -> []
      end

    firmware =
      if previous.firmware_version && entry.firmware_version &&
           previous.firmware_version != entry.firmware_version,
         do: [event(entry, "firmware_changed", previous.firmware_version, now)],
         else: []

    status ++ firmware ++ state_changes(entry, previous.state, now)
  end

  # A state the snapshot sets to a value it didn't have. One it leaves out is
  # no longer shown but isn't a change: the device has stopped saying, not
  # said something new.
  defp state_changes(%{state: nil}, _stored, _now), do: []

  defp state_changes(entry, stored, now) do
    for {name, value} <- Enum.sort(entry.state), get_in(stored, [name, "value"]) != value do
      entry
      |> event("state_changed", "", now)
      |> Map.merge(%{state: name, value: value})
    end
  end

  defp unlisted(entries, stored, now) do
    listed = MapSet.new(entries, &{&1.namespace, &1.serial})

    stored
    |> Enum.reject(fn {key, component} -> MapSet.member?(listed, key) or not component.listed end)
    |> Enum.map(fn {_key, component} ->
      events =
        if DeviceComponent.status(component) == :working,
          do: [event(component, "missing", "unlisted", now)],
          else: []

      {component.id, events}
    end)
    |> Enum.unzip()
    |> then(fn {ids, events} -> {ids, List.flatten(events)} end)
  end

  defp event(component, event, detail, at) do
    %{
      namespace: component.namespace,
      serial: component.serial,
      event: event,
      detail: detail,
      firmware_version: component.firmware_version || "",
      state: "",
      value: "",
      timestamp: at
    }
  end

  defp upsert([]), do: :ok

  defp upsert(rows) do
    {_count, _} =
      Repo.insert_all(DeviceComponent, rows,
        on_conflict: {:replace, @replaced},
        conflict_target: [:device_id, :namespace, :serial]
      )

    :ok
  end

  defp mark_unlisted([], _now), do: :ok

  defp mark_unlisted(ids, now) do
    {_count, _} =
      DeviceComponent
      |> where([c], c.id in ^ids)
      |> update([c],
        set: [
          listed: false,
          missing_since: fragment("COALESCE(?, ?)", c.missing_since, ^now),
          updated_at: ^now
        ]
      )
      |> Repo.update_all([])

    :ok
  end

  # ------------------------------------------------------------------ 0.2.0

  @typedoc """
  One `components:readings` report once `parse_readings/2` has read it: the
  component, when the device took the readings, and the readings kept, sorted
  by name.
  """
  @type readings_report() :: %{
          namespace: String.t(),
          serial: String.t(),
          timestamp: DateTime.t(),
          metrics: [{String.t(), float()}]
        }

  @doc """
  Reads a `components:readings` message's reports, skipping the ones that
  can't be read, as docs/components.md describes. Unlike a snapshot, one bad
  report doesn't cost the rest: each stands alone.
  """
  @spec parse_readings(term(), DateTime.t()) :: [readings_report()]
  def parse_readings(reports, now \\ DateTime.utc_now())

  def parse_readings(reports, now) when is_list(reports) do
    reports
    |> Enum.take(@max_reports_per_message)
    |> Enum.flat_map(&parse_report(&1, now))
  end

  def parse_readings(_reports, _now), do: []

  defp parse_report(
         %{"namespace" => namespace, "serial" => serial, "timestamp" => timestamp, "metrics" => metrics},
         now
       )
       when is_binary(namespace) and is_binary(serial) and is_binary(timestamp) and is_map(metrics) do
    with {:ok, at, _offset} <- DateTime.from_iso8601(timestamp),
         true <- abs(DateTime.diff(at, now, :second)) <= @max_reading_skew_seconds,
         [_ | _] = kept <- readings(metrics) do
      [%{namespace: namespace, serial: serial, timestamp: usec(at), metrics: kept}]
    else
      _ -> []
    end
  end

  defp parse_report(_report, _now), do: []

  # At most `@max_readings` names, in sorted order, so which are kept doesn't
  # depend on how the device's JSON library ordered them.
  defp readings(metrics) do
    metrics
    |> Enum.filter(fn {name, value} -> is_number(value) and Regex.match?(@name_pattern, name) end)
    |> Enum.sort()
    |> Enum.take(@max_readings)
    |> Enum.map(fn {name, value} -> {name, value / 1} end)
  end

  @doc """
  Records what a device's components measured: the latest value of each
  reading on the component's row, and every reading in ClickHouse.

  Reports for a component the device hasn't listed in a snapshot are ignored.
  How many there were comes back as `unknown`, so the extension can ask the
  device for its set.
  """
  @spec record_readings(DeviceInfo.t(), [readings_report()]) :: %{
          stored: non_neg_integer(),
          unknown: non_neg_integer()
        }
  def record_readings(%DeviceInfo{} = device_info, reports) when is_list(reports) do
    stored = components_by_key(device_info.device_id, reports)
    {known, unknown} = Enum.split_with(reports, &Map.has_key?(stored, {&1.namespace, &1.serial}))

    if known != [] do
      known
      |> Enum.group_by(&{&1.namespace, &1.serial})
      |> Enum.each(fn {key, component_reports} -> write_latest(Map.fetch!(stored, key), component_reports) end)

      :ok = write_readings(device_info, known, stored)
      broadcast(device_info.device_id)
    end

    %{stored: length(known), unknown: length(unknown)}
  end

  defp components_by_key(_device_id, []), do: %{}

  defp components_by_key(device_id, frames) do
    keys = MapSet.new(frames, &{&1.namespace, &1.serial})
    namespaces = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    serials = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    DeviceComponent
    |> where(device_id: ^device_id)
    |> where([c], c.namespace in ^namespaces and c.serial in ^serials)
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(keys, {&1.namespace, &1.serial}))
    |> Map.new(&{{&1.namespace, &1.serial}, &1})
  end

  # Merged into what is stored, so a component that reports its battery less
  # often than its temperature keeps both, and a report older than the stored
  # value of a reading doesn't replace it. The most recent `@max_readings`
  # names are kept, so one that stops being reported eventually goes.
  defp write_latest(component, reports) do
    readings =
      reports
      |> Enum.sort_by(& &1.timestamp, DateTime)
      |> Enum.reduce(component.readings, fn report, readings ->
        Enum.reduce(report.metrics, readings, fn {name, value}, readings ->
          if newer?(report.timestamp, readings[name]),
            do: Map.put(readings, name, %{"value" => value, "at" => DateTime.to_iso8601(report.timestamp)}),
            else: readings
        end)
      end)
      |> Enum.sort_by(fn {_name, %{"at" => at}} -> at end, :desc)
      |> Enum.take(@max_readings)
      |> Map.new()

    readings_at = readings |> Enum.map(fn {_name, %{"at" => at}} -> parse_time(at) end) |> Enum.max(DateTime)

    {_count, _} =
      DeviceComponent
      |> where(id: ^component.id)
      |> Repo.update_all(set: [readings: readings, readings_at: readings_at])

    :ok
  end

  defp newer?(_at, nil), do: true
  defp newer?(at, %{"at" => stored}), do: DateTime.compare(at, parse_time(stored)) != :lt

  defp parse_time(iso8601) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso8601)
    usec(at)
  end

  defp write_readings(device_info, reports, stored) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      firmware_uuid = firmware_uuid(device_info)

      reports
      |> Enum.flat_map(fn report ->
        component = Map.fetch!(stored, {report.namespace, report.serial})

        Enum.map(report.metrics, fn {key, value} ->
          %{
            timestamp: report.timestamp,
            org_id: device_info.org_id,
            product_id: device_info.product_id,
            device_id: device_info.device_id,
            namespace: report.namespace,
            serial: report.serial,
            key: key,
            value: value,
            firmware_uuid: firmware_uuid,
            firmware_version: component.firmware_version || ""
          }
        end)
      end)
      |> Enum.each(&Buffer.insert(DeviceComponentReading, DeviceComponentReading.changeset(&1)))
    end

    :ok
  end

  defp firmware_uuid(%DeviceInfo{firmware_metadata: %{uuid: uuid}}) when is_binary(uuid), do: uuid
  defp firmware_uuid(_device_info), do: ""

  @type state_rejection() :: :malformed | :unknown_component | :too_many_states

  @doc """
  Records a `components:state` change: the component's current state on its
  row, and the change in its history.

  Sending the value the state already has does nothing, so a device unsure
  whether a change arrived can send it again. So does a change older than the
  stored value, which a later change has already overtaken. A value a snapshot
  set is stamped with the platform's clock rather than the device's, so any
  change replaces it.
  """
  @spec record_state(DeviceInfo.t(), term(), DateTime.t()) :: :ok | {:error, state_rejection()}
  def record_state(%DeviceInfo{} = device_info, change, %DateTime{} = now \\ DateTime.utc_now()) do
    now = usec(now)

    with {:ok, change} <- parse_state(change, now),
         %DeviceComponent{} = component <-
           components_by_key(device_info.device_id, [change])[{change.namespace, change.serial}] ||
             {:error, :unknown_component},
         {:ok, state} <- put_state(component.state, change) do
      {_count, _} =
        DeviceComponent
        |> where(id: ^component.id)
        |> Repo.update_all(set: [state: state, updated_at: now])

      event =
        component
        |> event("state_changed", change.detail || "", change.changed_at)
        |> Map.merge(%{state: change.state, value: change.value})

      :ok = write_history(device_info, [event])
      broadcast(device_info.device_id)
    else
      :unchanged -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp parse_state(%{"namespace" => namespace, "serial" => serial, "state" => state, "value" => value} = change, now)
       when is_binary(namespace) and is_binary(serial) do
    detail = change["detail"]

    if state_name?(state) and state_value?(value) and detail?(detail) do
      {:ok,
       %{
         namespace: namespace,
         serial: serial,
         state: state,
         value: value,
         detail: if(detail != "", do: detail),
         changed_at: usec(device_time(change["changed_at"], now) || now)
       }}
    else
      {:error, :malformed}
    end
  end

  defp parse_state(_change, _now), do: {:error, :malformed}

  defp detail?(nil), do: true

  defp detail?(detail), do: is_binary(detail) and String.valid?(detail) and String.length(detail) <= @max_string_length

  defp put_state(state, change) do
    case state[change.state] do
      %{"value" => value} when value == change.value ->
        :unchanged

      %{"snapshot" => true} ->
        {:ok, Map.put(state, change.state, stored_change(change))}

      %{"since" => since} ->
        if DateTime.before?(change.changed_at, parse_time(since)),
          do: :unchanged,
          else: {:ok, Map.put(state, change.state, stored_change(change))}

      nil when map_size(state) >= @max_states ->
        {:error, :too_many_states}

      nil ->
        {:ok, Map.put(state, change.state, stored_change(change))}
    end
  end

  defp stored_change(change),
    do: %{"value" => change.value, "since" => DateTime.to_iso8601(change.changed_at), "detail" => change.detail}

  @doc """
  Forgets one of the device's components: deletes it and records who did.

  It comes back, as a new component, if the device lists it again.
  """
  @spec forget(Device.t(), pos_integer(), String.t()) :: :ok | {:error, :not_found}
  def forget(%Device{} = device, component_id, actor_name) do
    DeviceComponent
    |> where(id: ^component_id, device_id: ^device.id)
    |> select([c], c)
    |> Repo.delete_all()
    |> case do
      {1, [component]} ->
        device_info = %{org_id: device.org_id, product_id: device.product_id, device_id: device.id}
        event = event(component, "forgotten", actor_name, usec(DateTime.utc_now()))
        :ok = write_history(device_info, [event])
        broadcast(device.id)

      {0, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Asks the device for a fresh snapshot, having checked on its components where
  it can. Reaches the device only if it has the extension attached.
  """
  @spec request_refresh(Device.t()) :: :ok
  def request_refresh(%Device{id: device_id}) do
    ExtensionsPubSub.send_to_extension(device_id, :components, :refresh)
  end

  # ------------------------------------------------------------------ reads

  @doc """
  The device's components, grouped by namespace in the order the device page
  shows them: missing first within each group, then by name.
  """
  @spec list_for_device(Device.t()) :: [DeviceComponent.t()]
  def list_for_device(%Device{id: device_id}) do
    DeviceComponent
    |> where(device_id: ^device_id)
    |> order_by([c],
      asc: c.namespace,
      asc: c.listed and c.reachable,
      asc_nulls_last: c.name,
      asc: c.serial
    )
    |> Repo.all()
  end

  @doc "One of the device's components, or `nil`."
  @spec get_for_device(Device.t(), term()) :: DeviceComponent.t() | nil
  def get_for_device(%Device{id: device_id}, component_id) do
    case Integer.parse(to_string(component_id)) do
      {id, ""} -> Repo.get_by(DeviceComponent, id: id, device_id: device_id)
      _ -> nil
    end
  end

  @doc "How many of the device's components are missing."
  @spec missing_count(Device.t()) :: non_neg_integer()
  def missing_count(%Device{id: device_id}) do
    DeviceComponent
    |> where(device_id: ^device_id)
    |> where([c], not (c.listed and c.reachable))
    |> Repo.aggregate(:count)
  end

  @doc """
  The component's recent changes, newest first, from ClickHouse. Empty where
  analytics are off.
  """
  @spec history(DeviceComponent.t(), pos_integer()) :: [DeviceComponentHistory.t()]
  def history(%DeviceComponent{} = component, limit \\ 10) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      DeviceComponentHistory
      |> where(product_id: ^component.product_id, device_id: ^component.device_id)
      |> where(namespace: ^component.namespace, serial: ^component.serial)
      |> order_by(desc: :timestamp)
      |> limit(^limit)
      |> AnalyticsRepo.all()
    else
      []
    end
  end

  @typedoc """
  A component's readings over a window, for the sparklines on its panel:
  each reading's averages, oldest first, and which window they cover.
  """
  @type readings_history() :: %{
          window: :six_hours | :fourteen_days,
          series: %{String.t() => [{DateTime.t(), float()}]}
        }

  @doc """
  The component's readings over the last six hours, averaged in five-minute
  steps. A component that reports too rarely to draw a line in six hours, such
  as a lock's battery, gets the last fourteen days in four-hour steps instead.
  Empty where analytics are off.
  """
  @spec readings_history(DeviceComponent.t(), DateTime.t()) :: readings_history()
  def readings_history(%DeviceComponent{} = component, %DateTime{} = now \\ DateTime.utc_now()) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      six_hours = readings_series(component, :six_hours, DateTime.add(now, -6, :hour))

      if Enum.any?(six_hours, fn {_key, points} -> length(points) > 1 end),
        do: %{window: :six_hours, series: six_hours},
        else: %{
          window: :fourteen_days,
          series: readings_series(component, :fourteen_days, DateTime.add(now, -14, :day))
        }
    else
      %{window: :six_hours, series: %{}}
    end
  end

  defp readings_series(component, window, since) do
    component
    |> readings_since(since)
    |> bucketed(window)
    |> AnalyticsRepo.all()
    |> Enum.group_by(& &1.key, &{to_utc_datetime(&1.at), &1.value})
    |> Map.new(fn {key, points} -> {key, Enum.sort_by(points, &elem(&1, 0), DateTime)} end)
  end

  defp readings_since(component, since) do
    DeviceComponentReading
    |> where(product_id: ^component.product_id, device_id: ^component.device_id)
    |> where(namespace: ^component.namespace, serial: ^component.serial)
    |> where([r], r.timestamp >= ^since)
  end

  # Separate clauses because the interval has to be written into the SQL: a
  # bound parameter in the select wouldn't match the one in the GROUP BY.
  defp bucketed(query, :six_hours) do
    query
    |> group_by([r], [r.key, fragment("toStartOfFiveMinutes(?)", r.timestamp)])
    |> select([r], %{key: r.key, at: fragment("toStartOfFiveMinutes(?)", r.timestamp), value: avg(r.value)})
  end

  defp bucketed(query, :fourteen_days) do
    query
    |> group_by([r], [r.key, fragment("toStartOfInterval(?, INTERVAL 4 HOUR)", r.timestamp)])
    |> select([r], %{
      key: r.key,
      at: fragment("toStartOfInterval(?, INTERVAL 4 HOUR)", r.timestamp),
      value: avg(r.value)
    })
  end

  # Bucketing functions come back as a naive datetime or a datetime, depending
  # on the column type; both name the same instant in UTC.
  defp to_utc_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc_datetime(%DateTime{} = at), do: at

  @typedoc """
  How one of a component's states changed over a window: its value when the
  window began (`nil` if nothing says), and each change in it, oldest first.
  """
  @type state_history() :: %{
          String.t() => %{
            before: String.t() | nil,
            changes: [%{at: DateTime.t(), value: String.t(), detail: String.t()}]
          }
        }

  @doc """
  How each of the component's current states changed from `since` until now,
  for the timelines on its panel. Empty where analytics are off.
  """
  @spec state_history(DeviceComponent.t(), DateTime.t()) :: state_history()
  def state_history(%DeviceComponent{state: state} = component, %DateTime{} = since) when map_size(state) > 0 do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      names = Map.keys(state)

      base =
        DeviceComponentHistory
        |> where(product_id: ^component.product_id, device_id: ^component.device_id)
        |> where(namespace: ^component.namespace, serial: ^component.serial)
        |> where([h], h.event == "state_changed" and h.state in ^names)

      before =
        base
        |> where([h], h.timestamp < ^since)
        |> group_by([h], h.state)
        |> select([h], {h.state, fragment("argMax(?, ?)", h.value, h.timestamp)})
        |> AnalyticsRepo.all()
        |> Map.new()

      changes =
        base
        |> where([h], h.timestamp >= ^since)
        |> order_by(asc: :timestamp)
        |> select([h], %{state: h.state, at: h.timestamp, value: h.value, detail: h.detail})
        |> AnalyticsRepo.all()
        |> Enum.group_by(& &1.state, &Map.delete(&1, :state))

      Map.new(names, &{&1, %{before: before[&1], changes: Map.get(changes, &1, [])}})
    else
      %{}
    end
  end

  def state_history(%DeviceComponent{}, _since), do: %{}

  @doc """
  The product's components counted as the Components page shows them: how
  many there are, on how many devices, and how many are missing.
  """
  @spec product_counts(Product.t()) :: %{
          components: non_neg_integer(),
          devices: non_neg_integer(),
          working: non_neg_integer(),
          missing: non_neg_integer()
        }
  def product_counts(%Product{id: product_id}) do
    DeviceComponent
    |> where(product_id: ^product_id)
    |> select([c], %{
      components: count(c.id),
      devices: count(c.device_id, :distinct),
      missing: filter(count(c.id), not (c.listed and c.reachable))
    })
    |> Repo.one()
    |> then(&Map.put(&1, :working, &1.components - &1.missing))
  end

  @doc "How many of the product's components are missing, for the sidebar."
  @spec product_missing_count(Product.t() | pos_integer()) :: non_neg_integer()
  def product_missing_count(%Product{id: product_id}), do: product_missing_count(product_id)

  def product_missing_count(product_id) when is_integer(product_id) do
    DeviceComponent
    |> where(product_id: ^product_id)
    |> where([c], not (c.listed and c.reachable))
    |> Repo.aggregate(:count)
  end

  @doc """
  The product's components by model, most common first: how many, on how many
  devices, how many are missing and on how many devices, and the firmware
  versions they run, most common first (`nil` for those that don't say).
  """
  @spec models(Product.t()) :: [map()]
  def models(%Product{id: product_id}) do
    base = where(DeviceComponent, product_id: ^product_id)

    versions =
      base
      |> group_by([c], [c.namespace, c.vendor, c.model, c.firmware_version])
      |> select([c], {{c.namespace, c.vendor, c.model}, {c.firmware_version, count(c.id)}})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    base
    |> group_by([c], [c.namespace, c.vendor, c.model])
    |> select([c], %{
      namespace: c.namespace,
      vendor: c.vendor,
      model: c.model,
      vendor_name: max(c.vendor_name),
      model_name: max(c.model_name),
      count: count(c.id),
      devices: count(c.device_id, :distinct),
      missing: filter(count(c.id), not (c.listed and c.reachable)),
      missing_devices: filter(count(c.device_id, :distinct), not (c.listed and c.reachable))
    })
    |> order_by([c], desc: count(c.id), asc: c.namespace, asc: c.vendor, asc: c.model)
    |> Repo.all()
    |> Enum.map(fn model ->
      key = {model.namespace, model.vendor, model.model}

      model
      |> Map.put(:working, model.count - model.missing)
      |> Map.put(:firmware_versions, versions |> Map.get(key, []) |> Enum.sort_by(&elem(&1, 1), :desc))
    end)
  end

  # ------------------------------------------------------------------ effects

  # Tells an open device page to re-read the device's components.
  defp broadcast(device_id) do
    ExtensionsPubSub.broadcast_report(device_id, "components:updated", %{})
  end

  # Gated explicitly, as `NervesHub.Devices.Alarms` gates its history: a
  # deployment without analytics is a decision this code made.
  defp write_history(device_info, events) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Enum.each(events, fn event ->
        Buffer.insert(
          DeviceComponentHistory,
          DeviceComponentHistory.changeset(
            Map.merge(event, %{
              org_id: device_info.org_id,
              product_id: device_info.product_id,
              device_id: device_info.device_id
            })
          )
        )
      end)
    end

    :ok
  end

  # `insert_all` doesn't cast, and a time with no fractional seconds raises
  # against a `:utc_datetime_usec` column instead of being padded.
  defp usec(%DateTime{microsecond: {microsecond, _precision}} = at), do: %{at | microsecond: {microsecond, 6}}
end
