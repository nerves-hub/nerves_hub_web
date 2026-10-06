defmodule NervesHub.Repo.Migrations.IndexDevicesByProductAndVersionKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    # Deployment group matching compares devices' firmware versions against the
    # group's version requirement in the database, as ranges of
    # `semver_sort_key/1` (see NervesHub.ManagedDeployments.VersionRequirement).
    # Without an index that's a scan of every device, working out each one's key
    # as it goes. Matching is always within one product, so the product leads.
    #
    # `COLLATE "C"` has to match the queries' own, or Postgres won't use the
    # index. The key only orders correctly under it.
    create(
      index(
        :devices,
        [:product_id, ~s|(semver_sort_key(firmware_metadata ->> 'version') COLLATE "C")|],
        name: :devices_product_id_version_key_index,
        concurrently: true
      )
    )
  end
end
