defmodule NervesHub.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change() do
    create table(:product_notifications, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:product_id, references(:products), null: false)

      add(:level, :string, null: false)
      add(:title, :text, null: false)
      add(:message, :text, null: false)
      add(:metadata, :map, null: false, default: %{})

      add(:event_key, :string, null: false)
      add(:last_occurred_at, :utc_datetime, null: false)
      add(:occurrence_count, :integer, null: false, default: 1)

      timestamps()
    end

    create(index("product_notifications", [:product_id, desc: :last_occurred_at]))
    create(index("product_notifications", [:product_id, :event_key], unique: true))
  end
end
