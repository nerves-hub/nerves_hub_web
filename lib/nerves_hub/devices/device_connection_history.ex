defmodule NervesHub.Devices.DeviceConnectionHistory do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.DeviceConnection

  @type t :: %__MODULE__{}

  @version_counter {__MODULE__, :version}

  # Creating the counter as the module loads means it exists before any process
  # can call the module, so no two writers can race to create one each.
  @on_load :init_version_counter

  @primary_key false
  schema "device_connection_history" do
    field(:ref, Ch, type: "UUID")

    field(:established_at, Ch, type: "DateTime64(6, 'UTC')")
    field(:last_seen_at, Ch, type: "DateTime64(6, 'UTC')")
    field(:disconnected_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))")
    field(:expected_wake_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:disconnected_reason, Ch, type: "LowCardinality(String)")

    field(:lib, Ch, type: "LowCardinality(String)")
    field(:lib_version, Ch, type: "LowCardinality(String)")

    field(:network_interface, Ch, type: "LowCardinality(String)")

    field(:ip_address, Ch, type: "String")

    field(:version, Ch, type: "UInt64")
  end

  def from_device_connection_changeset(%DeviceConnection{} = connection) do
    %__MODULE__{}
    |> change()
    |> put_change(:org_id, connection.org_id)
    |> put_change(:product_id, connection.product_id)
    |> put_change(:device_id, connection.device_id)
    |> put_change(:established_at, connection.established_at)
    |> put_change(:last_seen_at, connection.last_seen_at)
    |> put_change(:disconnected_at, connection.disconnected_at)
    |> put_change(:expected_wake_at, connection.expected_wake_at)
    |> put_change(:ref, connection.id)
    # `disconnected_at` and `expected_wake_at` are the only Nullable columns on
    # the table; the String columns below are not, so an unset one has to
    # become "" rather than nil. The reason is stored as
    # `NervesHub.Devices.DisconnectReason` dumps it.
    |> put_change(:disconnected_reason, to_string(connection.disconnected_reason))
    |> put_change(:lib, to_string(connection.lib))
    |> put_change(:lib_version, to_string(connection.lib_version))
    |> put_change(:network_interface, to_string(connection.network_interface))
    |> put_change(:ip_address, connection.ip_address || "")
    |> put_change(:version, current_version())
  end

  # The `ReplacingMergeTree` dedupes on (org_id, product_id, device_id,
  # established_at), which every row for a single connection shares, and keeps
  # the row with the highest `version`. A connection's rows (connecting,
  # connected, heartbeats, disconnected) are usually written within the same
  # second, so a second-resolution version leaves them tied and ClickHouse picks
  # between them arbitrarily - the merged view could report an already
  # disconnected connection as still open.
  #
  # Microsecond resolution narrows that window but doesn't close it: two rows
  # can still land in the same microsecond, and a wall clock read can step
  # backwards when the host's clock is adjusted, which would put a disconnect
  # *behind* the heartbeat it follows. `System.system_time/1` reads the BEAM's
  # corrected clock, which never steps backwards, and the high water mark below
  # turns it into a strictly increasing sequence, so each row a node writes for
  # a connection beats the one before it.
  defp current_version() do
    next_version(:persistent_term.get(@version_counter), System.system_time(:microsecond))
  end

  defp next_version(counter, now) do
    previous = :atomics.get(counter, 1)
    version = max(now, previous + 1)

    case :atomics.compare_exchange(counter, 1, previous, version) do
      :ok -> version
      _bumped_concurrently -> next_version(counter, now)
    end
  end

  @doc """
  Builds a new history row from an existing one.

  Used when reconciling stale connections directly against the analytics store:
  the existing row is carried forward (same `ref`/`established_at`) with the
  disconnect details applied and a bumped `version` so the `ReplacingMergeTree`
  collapses to this disconnected state. It is closed as of `last_seen_at`, the
  last time anything heard from it, rather than when the stale connection was
  noticed, which can be an hour or more later.
  """
  def mark_as_stale_and_disconnected_changeset(%__MODULE__{} = connection) do
    connection
    |> change()
    |> put_change(:disconnected_at, connection.last_seen_at)
    |> put_change(:disconnected_reason, stale_reason(connection.disconnected_reason))
    |> put_change(:version, current_version())
  end

  # A reason already recorded, such as a sleep the device announced before its
  # radio dropped, says more than "stale" does.
  defp stale_reason(reason) when reason in [nil, ""], do: "stale_connection"
  defp stale_reason(reason), do: reason

  # Keeps the counter across a code reload so the high water mark isn't reset
  # back behind the versions already handed out.
  defp init_version_counter() do
    case :persistent_term.get(@version_counter, nil) do
      nil -> :persistent_term.put(@version_counter, :atomics.new(1, signed: false))
      _counter -> :ok
    end
  end
end
