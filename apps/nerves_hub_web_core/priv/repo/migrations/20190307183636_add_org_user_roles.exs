defmodule NervesHubWebCore.Repo.Migrations.AddOrgUserRoles do
  use Ecto.Migration

  alias NervesHubWebCore.Accounts.User.Role

  def change do
    Role.create_type()
    drop(index(:users_orgs, [:user_id, :org_id]))
    rename table(:users_orgs), to: table(:org_users)

    alter table(:org_users) do
      add(:role, Role.type())
      timestamps()
    end

    create(unique_index(:org_users, [:org_id, :user_id], name: "org_users_index"))
  end
end
