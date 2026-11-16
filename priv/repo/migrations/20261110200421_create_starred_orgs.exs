defmodule NervesHub.Repo.Migrations.CreateStarredOrgs do
  use Ecto.Migration

  def change() do
    create table(:starred_orgs) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:org_id, references(:orgs, on_delete: :delete_all), null: false)

      timestamps(updated_at: false)
    end

    # Also the index for user_id, which leads it.
    create(unique_index(:starred_orgs, [:user_id, :org_id]))
    create(index(:starred_orgs, [:org_id]))
  end
end
