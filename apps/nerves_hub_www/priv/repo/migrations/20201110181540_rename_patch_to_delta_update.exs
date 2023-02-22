defmodule NervesHubWebCore.Repo.Migrations.RenamePatchToDeltaUpdate do
  use Ecto.Migration

  def up do
    rename(table(:firmwares), :patchable, to: :delta_updatable)
    rename(table(:firmware_patches), to: table(:firmware_deltas))

    execute("ALTER SEQUENCE firmware_patches_id_seq RENAME TO firmware_deltas_id_seq;")
    execute("ALTER INDEX firmware_patches_pkey RENAME TO firmware_deltas_pkey")

    execute(
      "ALTER TABLE firmware_deltas RENAME CONSTRAINT firmware_patches_source_id_fkey TO firmware_deltas_source_id_fkey"
    )

    execute(
      "ALTER TABLE firmware_deltas RENAME CONSTRAINT firmware_patches_target_id_fkey TO firmware_deltas_target_id_fkey"
    )
  end

  def down do
    rename(table(:firmwares), :delta_updatable, to: :patchable)
    rename(table(:firmware_deltas), to: table(:firmware_patches))

    execute("ALTER SEQUENCE firmware_deltas_id_seq RENAME TO firmware_patches_id_seq;")
    execute("ALTER INDEX firmware_deltas_pkey RENAME TO firmware_patches_pkey")

    execute(
      "ALTER TABLE firmware_patches RENAME CONSTRAINT firmware_deltas_source_id_fkey TO firmware_patches_source_id_fkey"
    )

    execute(
      "ALTER TABLE firmware_patches RENAME CONSTRAINT firmware_deltas_target_id_fkey TO firmware_patches_target_id_fkey"
    )
  end
end
