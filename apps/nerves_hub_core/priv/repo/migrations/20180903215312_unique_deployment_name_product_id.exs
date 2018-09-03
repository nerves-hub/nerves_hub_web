defmodule NervesHubCore.Repo.Migrations.UniqueDeploymentNameProductId do
  use Ecto.Migration

  alias NervesHubCore.Repo
  alias NervesHubCore.Deployments
  alias NervesHubCore.Deployments.Deployment

  def up do
    deployments = Repo.all(Deployment)

    for deployment <- deployments do
      dep = Repo.preload(deployment, :firmware)
      Deployments.update_deployment(dep, %{})
    end

    alter table(:deployments) do
      modify(:product_id, references(:products), null: false)
    end

    create(unique_index(:deployments, [:product_id, :name]))
  end

  def down do
    alter table(:deployments) do
      drop(:product_id)
    end

    drop(unique_index(:deployments, [:product_id, :name]))
  end
end
