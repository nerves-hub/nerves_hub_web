defmodule NervesHub.Repo.Migrations.UniqueDeploymentNameProductId do
  use Ecto.Migration

  def up do
    alter table(:deployments) do
      modify(:product_id, references(:products), null: false)
    end

    create(unique_index(:deployments, [:product_id, :name]))
  end

  def down do
    drop(unique_index(:deployments, [:product_id, :name]))
  end
end
