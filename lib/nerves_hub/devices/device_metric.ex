defmodule NervesHub.Devices.DeviceMetric do
  use Ecto.Schema

  alias Ecto.Changeset
  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @required_params [:device_id, :key, :value]

  schema "device_metrics" do
    belongs_to(:device, Device)
    field(:key, :string)
    field(:value, :float)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def save(params) do
    %__MODULE__{}
    |> cast(params, @required_params)
    |> validate_required(@required_params)
    |> format_field(:key)
  end

  defp format_field(%Changeset{changes: %{key: key}} = cs, :key) do
    # Just remove spaces for now.
    formatted_key = String.replace(key, " ", "")

    put_change(cs, :key, formatted_key)
  end
end
