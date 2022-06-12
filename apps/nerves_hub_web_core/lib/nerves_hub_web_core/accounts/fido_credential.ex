defmodule NervesHubWebCore.Accounts.FidoCredential do
  use Ecto.Schema
  import Ecto.Changeset
  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Accounts.CoseKey

  schema "fido_credentials" do
    belongs_to(:user, User)
    field(:nickname, :string)
    field(:credential_id, :binary)

    field(:cose_key, CoseKey)
    field(:type, :binary)
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  @required_attrs ~w(user_id nickname credential_id cose_key type)a
  @cast_attrs @required_attrs

  def create_changeset(%__MODULE__{} = fido_credential, params) do
    fido_credential
    |> cast(params, @cast_attrs)
    |> validate_required(@required_attrs)
    |> unique_constraint(:credential_id, name: :fido_credentials_user_id_credential_id)
  end

  def nickname_changeset(%__MODULE__{} = changeset, params \\ %{}) do
    changeset
    |> cast(params, ~w(user_id nickname)a)
    |> validate_required(~w(user_id nickname)a)
    |> validate_length(:nickname, min: 3)
  end

  def delete_changeset(%__MODULE__{} = changeset) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    changeset
    |> cast(%{}, [])
    |> put_change(:deleted_at, deleted_at)
  end
end
