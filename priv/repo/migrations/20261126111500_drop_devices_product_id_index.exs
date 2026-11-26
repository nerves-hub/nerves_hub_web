defmodule NervesHub.Repo.Migrations.DropDevicesProductIdIndex do
  @moduledoc """
  `devices_product_id_identifier_index` covers `devices_product_id_index`.

  Postgres can use a btree index for a query on its leading columns alone, and
  the composite index leads with `product_id`. So it serves every lookup the
  single-column index did: counting or listing a product's devices, and the
  check `devices_product_id_fkey` makes when a product row is deleted. The
  single-column index only adds work to every write to `devices` and takes up
  space.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    drop_if_exists(index(:devices, [:product_id], name: :devices_product_id_index, concurrently: true))
  end

  def down() do
    create_if_not_exists(index(:devices, [:product_id], name: :devices_product_id_index, concurrently: true))
  end
end
