defmodule NervesHub.Repo.Migrations.CreateCustomHealthMetricsLabels do
  use Ecto.Migration

  def change() do
    create table(:custom_health_metrics_labels) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:key, :string, null: false)
      add(:label, :string, null: false)

      timestamps()
    end

    create(unique_index(:custom_health_metrics_labels, [:product_id, :key]))
  end
end
