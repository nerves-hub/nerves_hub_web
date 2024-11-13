defmodule NervesHub.Repo.Migrations.AddFeatures do
  use Ecto.Migration

  def change do
    create table(:features) do
      add :name, :text
      add :key, :text
      add :description, :text
    end

    create unique_index(:features, :key)

    create table(:product_features) do
      add :feature_id, references(:features)
      add :product_id, references(:products)
      add :allowed, :boolean, default: false, null: false
    end

    create unique_index(:product_features, [:feature_id, :product_id])

    create table(:device_product_features) do
      add :product_feature_id, references(:product_features)
      add :device_id, references(:devices)
      add :allowed, :boolean, default: false, null: false
    end

    create unique_index(:device_product_features, [:product_feature_id, :device_id])
  end
end
