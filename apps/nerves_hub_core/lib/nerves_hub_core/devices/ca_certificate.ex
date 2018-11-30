defmodule NervesHubCore.Devices.CACertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubCore.Accounts.Org

  @type t :: %__MODULE__{}

  @params [
    :org_id,
    :serial,
    :aki,
    :ski,
    :not_before,
    :not_after,
    :der
  ]

  schema "ca_certificates" do
    belongs_to(:org, Org)

    field(:serial, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:der, :binary)

    timestamps()
  end

  def changeset(%__MODULE__{} = ca_certificate, params) do
    ca_certificate
    |> cast(params, @params)
    |> validate_required(@params)
    |> unique_constraint(:serial, name: :ca_certificates_org_id_serial_index)
  end
end
