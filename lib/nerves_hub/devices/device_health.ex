defmodule NervesHub.Devices.DeviceHealth do
  @moduledoc """
  A device's current health status.

  One row per device, replaced in place. This used to be a report history with
  the whole report payload on every row, and `devices.latest_health_id`
  pointing at the newest — but nothing ever read a historical row, and of the
  payload only alarms and metadata were ever looked at. Those now live in
  `NervesHub.Devices.DeviceAlarm` and on the device connection's `metadata`,
  and the readings the payload also carried live in ClickHouse.

  What is left is the verdict: a status and, when a level is engaged, the
  reasons that engaged it. Status is derived from the profile thresholds and
  the stored readings, so a past status can be recomputed from ClickHouse
  rather than needing a history table of its own.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}

  @required_params [:device_id]
  @optional_params [:status, :status_reasons]

  schema "device_health" do
    belongs_to(:device, Device)

    field(:status, Ecto.Enum,
      values: [:unknown, :healthy, :warning, :unhealthy],
      default: :unknown
    )

    field(:status_reasons, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def save(params) do
    %__MODULE__{}
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:device_id)
  end
end
