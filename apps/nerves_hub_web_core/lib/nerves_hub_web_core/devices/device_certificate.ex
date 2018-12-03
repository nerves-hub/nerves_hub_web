defmodule NervesHubWebCore.Devices.DeviceCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Devices.{Device, DeviceCertificate}

  @type t :: %__MODULE__{}

  @params [
    :device_id,
    :serial,
    :aki,
    :ski,
    :not_after,
    :not_before
  ]

  schema "device_certificates" do
    belongs_to(:device, Device)

    field(:serial, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)

    timestamps()
  end

  def changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    |> cast(params, @params)
    |> validate_required(@params)
    |> unique_constraint(:serial, name: :device_certificates_device_id_serial_index)
  end
end
