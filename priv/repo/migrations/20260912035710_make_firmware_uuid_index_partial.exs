defmodule NervesHub.Repo.Migrations.MakeFirmwareUuidIndexPartial do
  @moduledoc """
  Let a deleted firmware's uuid be uploaded again.

  Deleting firmware retires the row rather than removing it, and the uuid is a
  property of the build, so the old unique index kept refusing the same build
  forever after. The refusal even arrived as "has this version been uploaded
  already?", which was true and unhelpful.

  Scoping the index to live firmware frees the uuid. The deleted row keeps
  naming it, which is what device history needs, and a fresh upload gets a new
  row alongside it. `get_firmware_by_product_and_uuid_query/3` is what keeps a
  uuid resolving to one firmware when both exist: live first, deleted as the
  fallback.

  Rolling back needs any duplicate uuids resolved first, since the index this
  restores does not allow them. The same applies as to
  `allow_unsigned_atomvm_firmware`, for the same reason: the migration exists to
  permit rows the old constraint refused.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    execute("DROP INDEX CONCURRENTLY IF EXISTS firmwares_product_id_uuid_index")

    create(
      unique_index(:firmwares, [:product_id, :uuid],
        where: "deleted_at IS NULL",
        name: :firmwares_product_id_uuid_index,
        concurrently: true
      )
    )
  end

  def down() do
    execute("DROP INDEX CONCURRENTLY IF EXISTS firmwares_product_id_uuid_index")

    create(
      unique_index(:firmwares, [:product_id, :uuid],
        name: :firmwares_product_id_uuid_index,
        concurrently: true
      )
    )
  end
end
