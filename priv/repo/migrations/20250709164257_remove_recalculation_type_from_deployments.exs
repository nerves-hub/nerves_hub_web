defmodule NervesHub.Repo.Migrations.RemoveRecalculationTypeFromDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      remove(:recalculation_type, :string)
    end
  end
end
