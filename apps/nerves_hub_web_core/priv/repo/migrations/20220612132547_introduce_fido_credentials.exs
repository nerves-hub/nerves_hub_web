defmodule NervesHubWebCore.Repo.Migrations.IntroduceWebauthn do
  use Ecto.Migration

  def change do
    create table(:fido_credentials) do
      add(:user_id, references(:users), null: false)
      add(:nickname, :string, null: false)
      add(:credential_id, :string, null: false)
      add(:cose_key, :bytea, null: false)
      add(:type, :string, null: false)
      add(:deleted_at, :utc_datetime)

      timestamps()
    end

    create index(:fido_credentials, [:deleted_at])
    create index(:fido_credentials, [:credential_id])
    create unique_index(:fido_credentials, [:user_id, :credential_id], name: :fido_credentials_user_id_credential_id)
  end
end
