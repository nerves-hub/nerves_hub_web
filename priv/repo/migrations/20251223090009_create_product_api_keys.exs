defmodule NervesHub.Repo.Migrations.CreateProductApiKeys do
  use Ecto.Migration

  def change do
    create table(:product_api_keys) do
      add(:product_id, references(:products), null: false)

      add(:key, :string, null: false)
      add(:name, :string)

      add(:deactivated_at, :utc_datetime)

      timestamps()
    end

    create index(:product_api_keys, [:key], unique: true)
    create index(:product_api_keys, [:product_id])
  end
end
