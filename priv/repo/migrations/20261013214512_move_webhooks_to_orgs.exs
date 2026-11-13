defmodule NervesHub.Repo.Migrations.MoveWebhooksToOrgs do
  @moduledoc """
  Webhooks belong to an organization rather than a product, and send the
  events of every product in it or of the products they list.

  `product_webhooks` is renamed rather than copied, so each webhook keeps its
  id and the deliveries already queued for it (Oban jobs that name it by id)
  still find it. Each existing webhook is limited to the product it belonged
  to, so it goes on sending exactly what it sent before.
  """
  use Ecto.Migration

  def up() do
    rename(table(:product_webhooks), to: table(:webhooks))
    execute("ALTER SEQUENCE product_webhooks_id_seq RENAME TO webhooks_id_seq")
    execute("ALTER INDEX product_webhooks_pkey RENAME TO webhooks_pkey")

    alter table(:webhooks) do
      add(:org_id, references(:orgs, on_delete: :delete_all))
      add(:all_products, :boolean, null: false, default: true)
    end

    execute("""
    UPDATE webhooks
    SET org_id = products.org_id, all_products = false
    FROM products
    WHERE products.id = webhooks.product_id
    """)

    execute("ALTER TABLE webhooks ALTER COLUMN org_id SET NOT NULL")

    create(index(:webhooks, [:org_id]))

    # The products a webhook is limited to, when it is not sending every
    # product's events (`all_products`).
    create table(:webhook_products, primary_key: false) do
      add(:webhook_id, references(:webhooks, on_delete: :delete_all), null: false)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
    end

    create(unique_index(:webhook_products, [:webhook_id, :product_id]))
    create(index(:webhook_products, [:product_id]))

    execute("INSERT INTO webhook_products (webhook_id, product_id) SELECT id, product_id FROM webhooks")

    # Takes its index and foreign key with it.
    alter table(:webhooks) do
      remove(:product_id)
    end
  end

  # A webhook goes back to one product. One sending every product's events,
  # or listing none, has no product to go back to and is removed; one listing
  # several keeps the first.
  def down() do
    alter table(:webhooks) do
      add(:product_id, references(:products, on_delete: :delete_all))
    end

    execute("""
    UPDATE webhooks
    SET product_id = scoped.product_id
    FROM (
      SELECT webhook_id, min(product_id) AS product_id
      FROM webhook_products
      GROUP BY webhook_id
    ) AS scoped
    WHERE scoped.webhook_id = webhooks.id AND NOT webhooks.all_products
    """)

    execute("DELETE FROM webhooks WHERE product_id IS NULL")
    execute("ALTER TABLE webhooks ALTER COLUMN product_id SET NOT NULL")

    drop(table(:webhook_products))

    alter table(:webhooks) do
      remove(:org_id)
      remove(:all_products)
    end

    execute("ALTER INDEX webhooks_pkey RENAME TO product_webhooks_pkey")
    execute("ALTER SEQUENCE webhooks_id_seq RENAME TO product_webhooks_id_seq")
    rename(table(:webhooks), to: table(:product_webhooks))

    create(index(:product_webhooks, [:product_id]))

    execute(
      "ALTER TABLE product_webhooks RENAME CONSTRAINT webhooks_product_id_fkey TO product_webhooks_product_id_fkey"
    )
  end
end
