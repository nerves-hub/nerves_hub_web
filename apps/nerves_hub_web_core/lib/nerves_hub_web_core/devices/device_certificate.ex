defmodule NervesHubWebCore.Devices.DeviceCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Devices.{Device, DeviceCertificate}

  @type t :: %__MODULE__{}

  @required_params [
    :org_id,
    :device_id,
    :serial,
    :aki,
    :not_after,
    :not_before
  ]
  @optional_params [
    :ski,
    :last_used
  ]

  schema "device_certificates" do
    belongs_to(:device, Device)
    belongs_to(:org, Org)

    field(:serial, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:last_used, :utc_datetime)

    timestamps()
  end

  def changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:serial, name: :device_certificates_device_id_serial_index)
  end

  def update_changeset(%DeviceCertificate{} = device_certificate, params) do
    device_certificate
    |> cast(params, [:last_used])
  end
end
