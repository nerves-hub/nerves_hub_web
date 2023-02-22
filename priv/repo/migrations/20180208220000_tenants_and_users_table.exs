defmodule NervesHubWebCore.Repo.Migrations.TenantsAndUsersTable do
  use Ecto.Migration

  def up do
    create table(:tenants) do
      add :name, :string, null: false

      timestamps()
    end

    create table(:users) do
      add :tenant_id, references(:tenants), null: false
      add :name, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
  end

  def down do
    drop table(:users)
    drop table(:tenants)
  end
end
