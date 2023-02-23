defmodule NervesHub.Repo.Migrations.RemoveUsersOrgs do
  use Ecto.Migration

  def change do
    drop(index(:users_orgs, [:user_id, :org_id]))
    drop(table(:users_orgs))
  end
end
