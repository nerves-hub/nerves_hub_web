defmodule NervesHub.Repo.Migrations.AddRecalculationTypeToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:recalculation_type, :text, default: "device", null: false)
    end
  end
end
