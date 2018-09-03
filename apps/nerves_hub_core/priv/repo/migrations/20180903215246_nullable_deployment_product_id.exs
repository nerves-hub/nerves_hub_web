defmodule NervesHubCore.Repo.Migrations.NullableDeploymentProductId do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:product_id, :integer)
    end
  end
end
