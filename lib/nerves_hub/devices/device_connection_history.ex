defmodule NervesHub.Devices.DeviceConnectionHistory do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.DeviceConnection

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_connection_history" do
    field(:ref, Ch, type: "UUID")

    field(:established_at, Ch, type: "DateTime64(6, 'UTC')")
    field(:last_seen_at, Ch, type: "DateTime64(6, 'UTC')")
    field(:disconnected_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:disconnected_reason, Ch, type: "LowCardinality(String)")

    field(:lib, Ch, type: "LowCardinality(String)")
    field(:lib_version, Ch, type: "LowCardinality(String)")

    field(:network_interface, Ch, type: "LowCardinality(String)")

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
    |> put_change(:ref, connection.id)
    |> put_change(:disconnected_reason, connection.disconnected_reason)
    |> put_change(:lib, connection.lib)
    |> put_change(:lib_version, connection.lib_version)
    |> put_change(:network_interface, to_string(connection.network_interface))
    |> put_change(:version, current_version())
  end

  # The `ReplacingMergeTree` dedupes on (org_id, product_id, device_id,
  # established_at), which every row for a single connection shares, and keeps
  # the row with the highest `version`. A connection's rows (connecting,
  # connected, heartbeats, disconnected) are usually written within the same
  # second, so a second-resolution version leaves them tied and ClickHouse picks
  # between them arbitrarily - the merged view could report an already
  # disconnected connection as still open. Microseconds keep the writes strictly
  # ordered, so the most recent one always wins.
  defp current_version(), do: DateTime.to_unix(DateTime.utc_now(), :microsecond)

  @doc """
  Builds a new history row from an existing one.

  Used when reconciling stale connections directly against the analytics store:
  the existing row is carried forward (same `ref`/`established_at`) with the
  disconnect details applied and a bumped `version` so the `ReplacingMergeTree`
  collapses to this disconnected state.
  """
  def mark_as_stale_and_disconnected_changeset(%__MODULE__{} = connection) do
    now = DateTime.utc_now()

    connection
    |> change()
    |> put_change(:disconnected_at, now)
    |> put_change(:disconnected_reason, "Stale connection")
    |> put_change(:version, DateTime.to_unix(now, :microsecond))
  end
end
