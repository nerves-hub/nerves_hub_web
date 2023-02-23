defmodule NervesHub.Repo.Migrations.AddOrgUserRoles do
  use Ecto.Migration

  alias NervesHub.Accounts.User.Role

  def change do
    Role.create_type()

    create table(:org_users) do
      add(:org_id, references(:orgs, on_delete: :delete_all))
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:role, Role.type())
      timestamps()
    end

    create(unique_index(:org_users, [:org_id, :user_id], name: "org_users_index"))
  end
end
