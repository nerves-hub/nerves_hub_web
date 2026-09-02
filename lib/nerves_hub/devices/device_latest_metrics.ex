defmodule NervesHub.Devices.DeviceLatestMetrics do
  @moduledoc """
  The most recent metric report from one device, denormalised into PostgreSQL.

  The history is in ClickHouse (`NervesHub.Devices.DeviceMetric`), which is the
  right place for it and the wrong place to filter a device list from: the
  devices index compares a metric value alongside tags, firmware and connection
  state in one query, and that query is PostgreSQL's. So the latest set is kept
  here, one row per device, replaced by each report.

  Written only by `NervesHub.Devices.Metrics.record/3`, and written with
  `insert_all` rather than through a changeset -- the upsert has to be able to
  decline an out-of-order report by writing no row at all.
  """

  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_latest_metrics" do
    belongs_to(:device, Device, primary_key: true)
    belongs_to(:product, Product)

    field(:metrics, :map, default: %{})
    field(:reported_at, :utc_datetime_usec)
  end
end
