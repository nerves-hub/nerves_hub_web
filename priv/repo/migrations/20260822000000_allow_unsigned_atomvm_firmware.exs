defmodule NervesHub.Repo.Migrations.AllowUnsignedAtomvmFirmware do
  @moduledoc """
  Widen "signed unless ESP-IDF" to cover a format that cannot be signed at all.

  Nothing in the packbeam world signs or verifies anything today: the tooling
  writes no signature and AtomVM checks none, so every AtomVM firmware arrives
  without a signing key. The previous constraint named ESP-IDF alone and would
  have refused all of them.

  This does not decide anything about signing packbeams later. The constraint
  already accepts a row with a key, so defining a signing convention — see
  `NervesHub.Firmwares.UpdateTool.AtomVM` — needs no migration.

  `IS NOT DISTINCT FROM` rather than `IN`: `tool` is nullable, and `NULL IN
  (...)` is NULL, which a CHECK accepts. A firmware with no tool and no key
  stays refused, as it was before.

  Rolling back needs the AtomVM rows deleted first, the same way the migration
  this replaces needed the unsigned ESP-IDF ones.
  """

  use Ecto.Migration

  def up() do
    execute("ALTER TABLE firmwares DROP CONSTRAINT firmwares_signed_unless_esp_idf")

    execute("""
    ALTER TABLE firmwares
      ADD CONSTRAINT firmwares_signed_unless_optional_format
      CHECK (
        org_key_id IS NOT NULL
        OR tool IS NOT DISTINCT FROM 'esp-idf'
        OR tool IS NOT DISTINCT FROM 'atomvm'
      )
    """)
  end

  def down() do
    execute("ALTER TABLE firmwares DROP CONSTRAINT firmwares_signed_unless_optional_format")

    execute("""
    ALTER TABLE firmwares
      ADD CONSTRAINT firmwares_signed_unless_esp_idf
      CHECK (org_key_id IS NOT NULL OR tool IS NOT DISTINCT FROM 'esp-idf')
    """)
  end
end
