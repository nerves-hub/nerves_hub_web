defmodule NervesHubCore.Accounts.UserCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubCore.Accounts.{User, UserCertificate}

  @type t :: %__MODULE__{}

  @params [
    :user_id,
    :serial,
    :description,
    :aki,
    :ski,
    :not_before,
    :not_after
  ]

  schema "user_certificates" do
    belongs_to(:user, User)

    field(:serial, :string)
    field(:description, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)

    timestamps()
  end

  def changeset(%UserCertificate{} = user_certificate, params) do
    user_certificate
    |> cast(params, @params)
    |> validate_required(@params)
    |> unique_constraint(:serial, name: :user_certificates_user_id_serial_index)
  end
end
