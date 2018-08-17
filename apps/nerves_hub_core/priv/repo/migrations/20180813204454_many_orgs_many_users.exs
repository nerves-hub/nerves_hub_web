defmodule NervesHubCore.Repo.Migrations.ManyOrgsManyUsers do
  use Ecto.Migration

  def change do
    create table(:users_orgs) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:org_id, references(:orgs, on_delete: :delete_all))
    end

    alter table(:users) do
      remove(:org_id)
    end
  end
end
