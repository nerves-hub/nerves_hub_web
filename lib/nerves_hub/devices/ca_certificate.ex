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
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:serial, name: :ca_certificates_serial_index)
    |> cast_assoc(:jitp)
  end

  def update_changeset(%CACertificate{} = ca_certificate, params) do
    cast(ca_certificate, params, @optional_params)
    |> cast_assoc(:jitp)
  end

  @required_ski_params [:ski, :description, :org_id]
  def ski_only_changeset(%CACertificate{} = ca_certificate, params) do
    ca_certificate
    |> cast(params, @required_ski_params)
    |> validate_required(@required_ski_params)
    |> unique_constraint(:serial, name: :ca_certificates_serial_index)
    |> add_ski_fields()
  end

  defp add_ski_fields(%{valid?: true} = c) do
    {serial, _} =
      get_field(c, :ski)
      |> :binary.encode_hex()
      |> Integer.parse(16)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    change(c, %{
      serial: to_string(serial),
      not_before: now,
      not_after: %{now | year: now.year + 30},
      der: "invalid"
    })
  end

  defp add_ski_fields(c), do: c
end
