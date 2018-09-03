defmodule NervesHubCore.Repo.Migrations.UniqueDeploymentNameProductId do
  use Ecto.Migration

  alias NervesHubCore.Repo
  alias NervesHubCore.Deployments.Deployment

  def up do
    deployments = Repo.all(Deployment)

    for deployment <- deployments do
      deployment
      |> Repo.preload(:firmware)
      |> Deployment.changeset(%{})
      |> Repo.update()
    end

    alter table(:deployments) do
      modify(:product_id, references(:products), null: false)
    end

    create(unique_index(:deployments, [:product_id, :name]))
  end

  def down do
    drop(unique_index(:deployments, [:product_id, :name]))
  end
end
