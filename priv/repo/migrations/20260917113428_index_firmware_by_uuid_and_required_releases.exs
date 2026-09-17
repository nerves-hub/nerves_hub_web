defmodule NervesHub.Repo.Migrations.IndexFirmwareByUuidAndRequiredReleases do
  @moduledoc """
  Index the two lookups the required release work leans on.

  A device names its firmware by uuid, so finding which release it is running
  means resolving `(product_id, uuid)` to a firmware. `firmwares_product_id_uuid_index`
  can't serve that: it is partial on live firmware, and a device can go on running
  firmware that has since been deleted, so the queries can't add the predicate that
  would let them use it. This index covers every row, deleted included.

  `earlier_required_release?/1` asks whether a deployment group has a required
  release before its current one, and it is asked on the way into most of the
  per-device queries. Without `required` in an index it reads every release the
  group has ever had, which is the slowest answer for the commonest case: no.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create(
      index(:firmwares, [:product_id, :uuid],
        name: :firmwares_product_id_uuid_all_index,
        concurrently: true
      )
    )

    create(
      index(:deployment_releases, [:deployment_group_id],
        where: "required",
        name: :deployment_releases_required_index,
        concurrently: true
      )
    )
  end

  def down() do
    execute("DROP INDEX CONCURRENTLY IF EXISTS firmwares_product_id_uuid_all_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS deployment_releases_required_index")
  end
end
