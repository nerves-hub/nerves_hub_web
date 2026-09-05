defmodule NervesHub.Devices.DeviceAlarm do
  @moduledoc """
  One alarm currently raised on one device.

  Rows exist only while the alarm is raised: resolving deletes, and both edges
  are recorded in ClickHouse as `NervesHub.Devices.DeviceAlarmHistory`. Every
  read this table serves is a "what is alarming now" question — the device
  page's list, a product's alarm types and counts, and the alarm filters on the
  device index — so keeping it to one row per raised alarm is what lets those
  stay indexed lookups.

  Alarm names arrive from the device's Erlang alarm handler carrying an
  `Elixir.` prefix. It is stripped on the way in (see
  `NervesHub.Devices.Alarms`), so what is stored is what is displayed and what
  a filter matches against.
  """

  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  schema "device_alarms" do
    belongs_to(:device, Device)
    belongs_to(:product, Product)

    field(:alarm, :string)
    field(:description, :string)

    # When the alarm was first seen raised. Reports carry the device's whole
    # current alarm set every time, so the upsert in `Alarms.sync/3`
    # deliberately does not touch this column — otherwise it would track the
    # last report rather than the start of the episode.
    field(:raised_at, :utc_datetime_usec)
  end
end
