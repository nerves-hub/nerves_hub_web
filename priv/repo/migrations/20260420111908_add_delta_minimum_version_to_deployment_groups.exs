defmodule NervesHub.Repo.Migrations.AddDeltaMinimumVersionToDeploymentGroups do
  use Ecto.Migration

  def change() do
    alter table(:deployments) do
      add(:delta_minimum_version, :string)
    end
  end
end
