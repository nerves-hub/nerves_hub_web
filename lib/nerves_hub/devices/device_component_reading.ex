defmodule NervesHub.Devices.DeviceComponentReading do
  @moduledoc """
  One reading of one metric on one of a device's components: a probe's
  temperature, a lock's battery.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`, one per
  metric, as `NervesHub.Devices.DeviceMetric` stores a device's own. The
  latest value of each is kept on the component in PostgreSQL
  (`NervesHub.Devices.DeviceComponent`); this is the history behind the
  sparklines on a component's panel. Dropped after thirty days by the table's
  TTL.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_component_readings" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:namespace, Ch, type: "LowCardinality(String)")
    field(:serial, Ch, type: "String")

    field(:key, Ch, type: "LowCardinality(String)")
    field(:value, Ch, type: "Float64")

    # The device's firmware, and the component's, when the reading was taken.
    field(:firmware_uuid, Ch, type: "LowCardinality(String)", default: "")
    field(:firmware_version, Ch, type: "LowCardinality(String)", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch. Changes the struct
  directly rather than casting, as `DeviceMetric` does: the values are checked
  before they get here.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end
