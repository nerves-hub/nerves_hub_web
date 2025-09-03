defmodule NervesHub.Devices.CACertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.CACertificate.JITP

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
    :check_expiration,
    :last_used
  ]

  @derive {Phoenix.Param, key: :serial}
  schema "ca_certificates" do
    field(:aki, :binary)
    field(:check_expiration, :boolean)
    field(:der, :binary)
    field(:description, :string)
    field(:last_used, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:not_before, :utc_datetime)
    field(:serial, :string)
    field(:ski, :binary)

    belongs_to(:jitp, JITP)
    belongs_to(:org, Org, where: [deleted_at: nil])

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
    ca_certificate
    |> cast(params, @optional_params)
    |> cast_assoc(:jitp)
  end
end
