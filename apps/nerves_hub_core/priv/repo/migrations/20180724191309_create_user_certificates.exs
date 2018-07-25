defmodule NervesHubCore.Repo.Migrations.CreateUserCertificates do
  use Ecto.Migration

  def change do
    create table(:user_certificates) do
      add(:serial, :string, null: false)
      add(:description, :string, null: false)
      add(:user_id, references(:users, null: false))

      timestamps()
    end

    create(index(:user_certificates, [:user_id]))
    create(index(:user_certificates, [:serial]))
    unique_index(:user_certificates, [:user_id, :serial], name: :user_certificates_user_id_serial_index)
  end
end
