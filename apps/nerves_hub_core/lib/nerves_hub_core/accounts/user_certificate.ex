defmodule NervesHubCore.Accounts.UserCertificate do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubCore.Accounts.{User, UserCertificate}

  @type t :: %__MODULE__{}

  schema "user_certificates" do
    belongs_to(:user, User)

    field(:description, :string)
    field(:serial, :string)

    timestamps()
  end

  def changeset(%UserCertificate{} = user_certificate, params) do
    user_certificate
    |> cast(params, [:serial, :description])
    |> validate_required([:serial, :description])
    |> unique_constraint(:serial, name: :user_certificates_user_id_serial_index)
  end
end
