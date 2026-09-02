defmodule NervesHub.Devices.DeviceMetric do
  @moduledoc """
  One reading of one metric on one device.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer` and read on
  the device's health tab -- one key over a time window, for a chart. The
  *latest* value of every key is not read from here at all: that lives in
  PostgreSQL, denormalised, because it has to be filterable alongside the rest
  of a device's state in one query.

  Each reading carries the firmware the device was running when it took it, so
  a metric can be read per release and not only per device.

  Readings are dropped after thirty days by the table's TTL.

  ## One row per key, not one row per report

  Metric names come from the device -- `NervesHub.Extensions.Health` stores
  whatever keys a report carries -- so a column per metric is not available,
  and a report is stored as a row per key sharing one timestamp.
  `NervesHub.Devices.Metrics` caps how long a name may be and how many a report
  may carry, which is what keeps the `LowCardinality` column paying for itself.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_metrics" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:key, Ch, type: "LowCardinality(String)")
    field(:value, Ch, type: "Float64")

    # What the device was running when it took the reading. Bounded per product,
    # so `LowCardinality` pays off, and it is what lets a metric be read per
    # release rather than only per device.
    field(:firmware_uuid, Ch, type: "LowCardinality(String)", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Changes the struct directly rather than casting, the same as
  `NervesHub.ErrorReports.ErrorReport`: `NervesHub.Devices.Metrics` has already
  checked the key and coerced the value by this point, so a second pass through
  `cast/3` would only re-check what is known good. The buffer flattens the
  changeset back through the struct, which is what fills in any field left
  untouched -- `insert_all` builds one statement per batch, so every row has to
  carry the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end
