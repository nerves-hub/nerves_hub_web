defmodule NervesHub.Repo.Migrations.AddRollingUpdateFieldsToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:concurrent_updates, :integer, default: 10, null: false)
    end
  end
end
