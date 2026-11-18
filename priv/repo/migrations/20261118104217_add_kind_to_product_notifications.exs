defmodule NervesHub.Repo.Migrations.AddKindToProductNotifications do
  use Ecto.Migration

  # Every notification's event key starts with its kind, so existing rows can
  # be given one. A key that starts with anything else is left without a kind,
  # and the web UI shows the title and message it was stored with.
  @kinds ~w(
    chat_webhook_disabled
    connecting_code_failure
    device_bulk_create
    duplicate_device_identifier
    extension_failure
    missing_firmware_metadata
    oversized_metric_keys
    slack_subscription_disabled
    soft_deleted_device
    too_many_metrics
    update_mode_revert_failed
    webhook_disabled
    workflow_halted
    wrong_websocket_host
  )

  def up() do
    # Nullable with no default, so adding it doesn't rewrite the table.
    alter table(:product_notifications) do
      add(:kind, :string)
    end

    execute("""
    UPDATE product_notifications
    SET kind = split_part(event_key, '-', 1)
    WHERE split_part(event_key, '-', 1) IN (#{Enum.map_join(@kinds, ", ", &"'#{&1}'")})
    """)

    # The list rolls up a product's notifications of one kind into a card.
    create(index(:product_notifications, [:product_id, :kind, desc: :last_occurred_at]))
  end

  def down() do
    drop(index(:product_notifications, [:product_id, :kind, desc: :last_occurred_at]))

    alter table(:product_notifications) do
      remove(:kind)
    end
  end
end
