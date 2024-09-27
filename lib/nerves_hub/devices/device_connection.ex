defmodule NervesHub.Devices.DeviceConnection do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}
  @required_params [:device_id, :status, :last_seen_at]
  @wanted_params @required_params ++ [:metadata]

  schema "device_connections" do
    belongs_to(:device, Device)
    field(:established_at, :utc_datetime)
    field(:last_seen_at, :utc_datetime)
    field(:disconnected_at, :utc_datetime)
    field(:disconnected_reason, :string)
    field(:metadata, :map, default: %{})
    field(:status, Ecto.Enum, values: [:connected, :disconnected])
  end

  def connected_changeset(params) do
    %__MODULE__{}
    |> cast(params, @wanted_params ++ [:established_at])
    |> validate_required(@required_params ++ [:established_at])
  end

  def disconnected_changeset(params) do
    %__MODULE__{}
    |> cast(
      params,
      @wanted_params ++
        [
          :disconnected_at,
          :disconnected_reason
        ]
    )
    |> validate_required(@required_params ++ [:disconnected_at])
  end

  def heartbeat_changeset(params) do
    %__MODULE__{}
    |> cast(params, @wanted_params ++ [:established_at])
    |> validate_required(@required_params ++ [:established_at])
  end
end
