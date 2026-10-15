defmodule NervesHub.Repo.Migrations.CreateProductWebhooks do
  use Ecto.Migration

  def change() do
    create table(:product_webhooks) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:url, :text, null: false)
      add(:description, :string)
      add(:secret, :string, null: false)
      add(:events, {:array, :string}, null: false, default: [])
      add(:enabled, :boolean, null: false, default: true)
      add(:disabled_reason, :string)
      add(:failing_since, :utc_datetime)
      add(:last_error, :text)
      add(:last_error_at, :utc_datetime)

      timestamps()
    end

    create(index(:product_webhooks, [:product_id]))
  end
end
