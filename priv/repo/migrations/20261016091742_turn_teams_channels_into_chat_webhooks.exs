defmodule NervesHub.Repo.Migrations.TurnTeamsChannelsIntoChatWebhooks do
  use Ecto.Migration

  # Teams channels become chat webhooks: a channel posted to through the
  # incoming webhook its chat service gave, Microsoft Teams or Discord. The
  # tables are renamed, not replaced, so the Teams channels already added
  # keep working, and `provider` says which service each is.

  # {kind, old name, new name}, for what Ecto looks up by name: primary keys,
  # foreign keys, indexes and sequences.
  @renames [
    {:constraint, "chat_webhooks", "teams_channels_pkey", "chat_webhooks_pkey"},
    {:constraint, "chat_webhooks", "teams_channels_org_id_fkey", "chat_webhooks_org_id_fkey"},
    {:index, nil, "teams_channels_org_id_index", "chat_webhooks_org_id_index"},
    {:sequence, nil, "teams_channels_id_seq", "chat_webhooks_id_seq"},
    {:constraint, "chat_webhook_products", "teams_channel_products_channel_id_fkey",
     "chat_webhook_products_chat_webhook_id_fkey"},
    {:constraint, "chat_webhook_products", "teams_channel_products_product_id_fkey",
     "chat_webhook_products_product_id_fkey"},
    {:index, nil, "teams_channel_products_channel_id_product_id_index",
     "chat_webhook_products_chat_webhook_id_product_id_index"},
    {:index, nil, "teams_channel_products_product_id_index", "chat_webhook_products_product_id_index"},
    {:constraint, "chat_webhook_pending_events", "teams_pending_events_pkey", "chat_webhook_pending_events_pkey"},
    {:constraint, "chat_webhook_pending_events", "teams_pending_events_channel_id_fkey",
     "chat_webhook_pending_events_chat_webhook_id_fkey"},
    {:index, nil, "teams_pending_events_channel_id_id_index", "chat_webhook_pending_events_chat_webhook_id_id_index"},
    {:sequence, nil, "teams_pending_events_id_seq", "chat_webhook_pending_events_id_seq"}
  ]

  def up() do
    rename(table(:teams_channels), to: table(:chat_webhooks))
    rename(table(:teams_channel_products), to: table(:chat_webhook_products))
    rename(table(:teams_pending_events), to: table(:chat_webhook_pending_events))
    rename(table(:chat_webhook_products), :channel_id, to: :chat_webhook_id)
    rename(table(:chat_webhook_pending_events), :channel_id, to: :chat_webhook_id)

    # Every chat webhook so far is a Teams one; from here on each says.
    alter table(:chat_webhooks) do
      add(:provider, :string, null: false, default: "teams")
    end

    execute("ALTER TABLE chat_webhooks ALTER COLUMN provider DROP DEFAULT")

    for {kind, table, old, new} <- @renames, do: execute(rename_sql(kind, table, old, new))

    # Jobs already queued to post Teams events would otherwise name a worker
    # that no longer exists.
    execute("""
    UPDATE oban_jobs
    SET worker = 'NervesHub.Workers.PostChatWebhookEvents',
        queue = 'chat_webhooks',
        args = jsonb_build_object('chat_webhook_id', args->'channel_id')
    WHERE worker = 'NervesHub.Workers.PostTeamsEvents'
    """)
  end

  def down() do
    execute("""
    UPDATE oban_jobs
    SET worker = 'NervesHub.Workers.PostTeamsEvents',
        queue = 'teams',
        args = jsonb_build_object('channel_id', args->'chat_webhook_id')
    WHERE worker = 'NervesHub.Workers.PostChatWebhookEvents'
    """)

    # A Teams channel table cannot hold the other services' webhooks.
    execute("DELETE FROM chat_webhooks WHERE provider <> 'teams'")

    # Constraints are renamed back while their tables still have the new
    # names, which are the ones `@renames` gives.
    for {kind, table, old, new} <- Enum.reverse(@renames), do: execute(rename_sql(kind, table, new, old))

    alter table(:chat_webhooks) do
      remove(:provider)
    end

    rename(table(:chat_webhook_pending_events), :chat_webhook_id, to: :channel_id)
    rename(table(:chat_webhook_products), :chat_webhook_id, to: :channel_id)
    rename(table(:chat_webhook_pending_events), to: table(:teams_pending_events))
    rename(table(:chat_webhook_products), to: table(:teams_channel_products))
    rename(table(:chat_webhooks), to: table(:teams_channels))
  end

  defp rename_sql(:constraint, table, old, new), do: "ALTER TABLE #{table} RENAME CONSTRAINT #{old} TO #{new}"
  defp rename_sql(:index, _table, old, new), do: "ALTER INDEX #{old} RENAME TO #{new}"
  defp rename_sql(:sequence, _table, old, new), do: "ALTER SEQUENCE #{old} RENAME TO #{new}"
end
