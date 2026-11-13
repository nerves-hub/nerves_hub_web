defmodule NervesHub.Repo.Migrations.CreateSlackSubscriptions do
  use Ecto.Migration

  def change() do
    # A Slack channel an organization's device events are posted to.
    create table(:slack_subscriptions) do
      add(:connection_id, references(:slack_connections, on_delete: :delete_all), null: false)
      add(:channel_id, :string, null: false)
      add(:channel_name, :string, null: false)
      add(:events, {:array, :string}, null: false, default: [])
      add(:all_products, :boolean, null: false, default: true)
      add(:enabled, :boolean, null: false, default: true)
      add(:disabled_reason, :string)
      add(:last_error, :text)
      add(:last_error_at, :utc_datetime)

      timestamps()
    end

    create(unique_index(:slack_subscriptions, [:connection_id, :channel_id]))

    # The products a subscription is limited to, when it is not posting every
    # product's events (`all_products`).
    create table(:slack_subscription_products, primary_key: false) do
      add(:subscription_id, references(:slack_subscriptions, on_delete: :delete_all), null: false)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
    end

    create(unique_index(:slack_subscription_products, [:subscription_id, :product_id]))
    create(index(:slack_subscription_products, [:product_id]))

    # Events waiting to be posted, gathered so that a burst goes out as one
    # message rather than one per device.
    create table(:slack_pending_events) do
      add(:subscription_id, references(:slack_subscriptions, on_delete: :delete_all), null: false)
      add(:type, :string, null: false)
      add(:data, :map, null: false)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:slack_pending_events, [:subscription_id, :id]))
  end
end
