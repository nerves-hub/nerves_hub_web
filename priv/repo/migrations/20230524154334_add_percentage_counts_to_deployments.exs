defmodule NervesHub.Repo.Migrations.AddPercentageCountsToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:total_updating_devices, :integer, default: 0, null: false)
      add(:current_updated_devices, :integer, default: 0, null: false)
    end

    create index(:devices, :deployment_id)
  end
end
