defmodule NervesHub.Devices.DeviceConnection do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @primary_key {:id, UUIDv7, autogenerate: true}

  schema "latest_device_connections" do
    belongs_to(:device, Device)

    field(:established_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:disconnected_at, :utc_datetime_usec)
    field(:disconnected_reason, :string)
    field(:metadata, :map, default: %{})

    field(:status, Ecto.Enum,
      values: [:connecting, :connected, :disconnected],
      default: :connecting
    )
  end

  def connecting_changeset(device) do
    now = DateTime.utc_now()

    %__MODULE__{}
    |> change()
    |> put_assoc(:device, device)
    |> put_change(:established_at, now)
    |> put_change(:last_seen_at, now)
    |> put_change(:status, :connecting)
  end
end
