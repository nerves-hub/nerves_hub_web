defmodule NervesHub.Devices.DeviceConnection do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @primary_key {:id, UUIDv7, autogenerate: true}
  @required_params [:device_id, :status, :last_seen_at, :established_at]
  @wanted_on_create @required_params ++ [:metadata]
  @wanted_on_update @required_params ++ [:disconnected_at, :disconnected_reason, :metadata]

  schema "device_connections" do
    belongs_to(:device, Device)
    field(:established_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:disconnected_at, :utc_datetime_usec)
    field(:disconnected_reason, :string)
    field(:metadata, :map, default: %{})
    field(:status, Ecto.Enum, values: [:connected, :disconnected], default: :connected)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, @wanted_on_create)
    |> validate_required(@required_params)
  end

  def update_changeset(connection, params) do
    connection
    |> cast(params, @wanted_on_update)
    |> validate_required(@required_params)
  end
end
