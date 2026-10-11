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
    :not_before,
    :not_after,
    :der
  ]

  @optional_params [
    :description,
    :check_expiration,
    :last_used
  ]

  # A device certificate names its signer by its AKI, which is matched against
  # the CA's SKI, so a CA without an SKI could never sign a device in.
  @missing_ski_message "is missing. Add a Subject Key Identifier extension to the CA certificate, " <>
                         "which NervesHub uses to match device certificates to it"

  @derive {Phoenix.Param, key: :serial}
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
    field(:check_expiration, :boolean)

    timestamps()
  end

  def changeset(%__MODULE__{} = ca_certificate, params) do
    ca_certificate
    # A self-signed root CA may leave out its own AKI (RFC 5280, 4.2.1.1), and
    # nothing reads a CA's AKI, so it is stored when present and not required.
    |> cast(params, [:aki, :ski] ++ @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_required(:ski, message: @missing_ski_message)
    |> unique_constraint(:serial, name: :ca_certificates_serial_index)
    |> cast_assoc(:jitp)
  end

  def update_changeset(%CACertificate{} = ca_certificate, params) do
    ca_certificate
    |> cast(params, @optional_params)
    |> cast_assoc(:jitp)
  end
end
