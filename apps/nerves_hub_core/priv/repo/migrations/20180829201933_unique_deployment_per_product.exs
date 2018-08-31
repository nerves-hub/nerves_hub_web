defmodule NervesHubCore.Repo.Migrations.UniqueDeploymentPerProduct do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:product_id, references(:products), null: false)
    end

    create(unique_index(:deployments, [:product_id, :name]))
  end
end
