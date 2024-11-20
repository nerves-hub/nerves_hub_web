defmodule NervesHub.Repo.Migrations.RemoveDeploymentsRecalculationType do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      remove :recalculation_type
    end
  end
end
