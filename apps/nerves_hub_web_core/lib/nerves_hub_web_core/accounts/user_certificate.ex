defmodule NervesHubWebCore.Accounts.UserCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.{User, UserCertificate}

  @type t :: %__MODULE__{}

  @required_params [
    :user_id,
    :serial,
    :description,
    :aki,
    :ski,
    :not_before,
    :not_after
  ]

  @optional_params [
    :last_used
  ]

  schema "user_certificates" do
    belongs_to(:user, User)

    field(:serial, :string)
    field(:description, :string)
    field(:aki, :binary)
    field(:ski, :binary)
    field(:not_before, :utc_datetime)
    field(:not_after, :utc_datetime)
    field(:last_used, :utc_datetime)

    timestamps()
  end

  def changeset(%UserCertificate{} = user_certificate, params) do
    user_certificate
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:serial, name: :user_certificates_user_id_serial_index)
  end

  def update_changeset(%UserCertificate{} = user_certificate, params) do
    user_certificate
    |> cast(params, [:description, :last_used])
  end
end
