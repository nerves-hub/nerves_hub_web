defmodule NervesHubWebCore.Repo.Migrations.CreateOrgLimitsTable do
  use Ecto.Migration

  def change do
    create table(:org_limits) do
      add(:org_id, references(:orgs, null: false))
      add(:firmware_size, :integer, null: false)

      timestamps()
    end

    create(index(:org_limits, [:org_id]))
  end
end
