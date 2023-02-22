defmodule NervesHubWebCore.Devices.CACertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Devices.CACertificate
  alias NervesHubWebCore.Devices.CACertificate.JITP

  @type t :: %__MODULE__{}

  @required_params [
    :org_id,
    :serial,
    :aki,
    :ski,
    :not_before,
    :not_after,
    :der
  ]

  @optional_params [
    :description,
    :last_used
  ]

  schema "ca_certificates" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:jitp, JITP)

    field(:description, :string)
    field(:serial, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:last_used, :utc_datetime)
    field(:der, :binary)

    timestamps()
  end

  def changeset(%__MODULE__{} = ca_certificate, params) do
    ca_certificate
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:serial, name: :ca_certificates_serial_index)
    |> cast_assoc(:jitp)
  end

  def update_changeset(%CACertificate{} = ca_certificate, params) do
    cast(ca_certificate, params, [:description, :last_used])
    |> cast_assoc(:jitp)
  end
end
