defmodule NervesHub.Repo.Migrations.AddCreatedByToOrgKey do
  use Ecto.Migration

  def change do
    alter table(:org_keys) do
      add(:created_by_id, references(:users))
    end
  end
end
