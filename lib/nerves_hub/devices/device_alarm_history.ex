defmodule NervesHub.Devices.DeviceAlarmHistory do
  @moduledoc """
  One alarm transition on one device: a raise or a resolve.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`. Where
  `NervesHub.Devices.DeviceAlarm` answers "what is alarming now", this answers
  "what has alarmed, and for how long" — an episode is a raise paired with the
  next resolve, which is a window function over the pair rather than a row this
  has to keep mutable.

  Only transitions are written, never the steady state, so the volume is a
  fraction of `device_metrics` even though rows are kept three times as long.

  ## Why edges and not episodes

  A device reports its whole current alarm set on every health report, so the
  platform derives transitions by diffing against what it already holds. Edges
  fall straight out of that diff and are append-only, which is what the buffer
  batches and what MergeTree wants. Storing an episode instead would mean going
  back to mutate a row when the alarm clears, which ClickHouse is the wrong
  store for.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_alarm_history" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    # Without the `Elixir.` prefix, matching `device_alarms` in PostgreSQL.
    field(:alarm, Ch, type: "LowCardinality(String)")

    # "raised" or "resolved".
    field(:event, Ch, type: "LowCardinality(String)")

    # Carried on a raise; empty on a resolve, which has nothing new to say.
    field(:description, Ch, type: "String", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Changes the struct directly rather than casting, as `DeviceMetric` does:
  `NervesHub.Devices.Alarms` has already normalised the name and decided the
  event by this point. The buffer flattens the changeset back through the
  struct to fill in untouched fields, since `insert_all` builds one statement
  per batch and every row has to carry the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end
