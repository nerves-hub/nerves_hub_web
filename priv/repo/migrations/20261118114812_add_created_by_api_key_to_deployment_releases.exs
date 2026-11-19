defmodule NervesHub.Repo.Migrations.AddCreatedByApiKeyToDeploymentReleases do
  use Ecto.Migration

  def change() do
    alter table(:deployment_releases) do
      # Filled in instead of `created_by_id` when a product API key made the
      # release, which is the usual case for one published from CI.
      add(:created_by_api_key_id, references(:product_api_keys, on_delete: :nilify_all))
    end

    create(index(:deployment_releases, [:created_by_api_key_id]))
  end
end
