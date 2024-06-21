defmodule NervesHub.Devices.DeviceHealth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  alias __MODULE__

  @type t :: %__MODULE__{}
  @required_params [:device_id, :data]

  schema "device_health" do
    belongs_to(:device, Device)
    field(:data, :map)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def save(params) do
    dbg(params)

    %DeviceHealth{}
    |> cast(params, @required_params)
    |> validate_required(@required_params)
  end
end
