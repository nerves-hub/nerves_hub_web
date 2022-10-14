defmodule NervesHubWebCore.Repo.Migrations.MoveDeltaUpdatableToDeployments do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:deployments) do
      add(:delta_updatable, :boolean, default: false)
    end

    execute(&execute_up/0, &execute_down/0)

    alter table(:products) do
      remove(:delta_updatable, :boolean, default: false)
    end
  end

  defp execute_up() do
    query =
      from d in "deployments",
        join: p in "products",
        on: d.product_id == p.id,
        where: p.delta_updatable

    repo().update_all(query, [set: [delta_updatable: true]])
  end

  defp execute_down() do
    query =
      from p in "products",
        join: d in "deployments",
        on: d.product_id == p.id,
        on: d.delta_updatable

    repo().update_all(query, [set: [delta_updatable: true]])
  end
end
