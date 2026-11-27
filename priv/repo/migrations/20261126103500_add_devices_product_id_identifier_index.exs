defmodule NervesHub.Repo.Migrations.AddDevicesProductIdIdentifierIndex do
  @moduledoc """
  A product's devices in identifier order, the order the API and web UI
  devices lists default to.

  Without it, Postgres gets the first page of a product's devices either by
  walking `devices_identifier_index` across every product's devices until it
  has found enough of this one's, or by reading and sorting all of the
  product's devices.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create(index(:devices, [:product_id, :identifier], concurrently: true))
  end
end
