defmodule NervesHub.Repo.Migrations.AddOrgUserRoles do
  use Ecto.Migration

  def change do
    execute "create type role as enum ('admin', 'delete', 'write', 'read');", "drop type role;"

    create table(:org_users) do
      add(:org_id, references(:orgs, on_delete: :delete_all))
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:role, :role)
      timestamps()
    end

    create(unique_index(:org_users, [:org_id, :user_id], name: "org_users_index"))
  end
end
