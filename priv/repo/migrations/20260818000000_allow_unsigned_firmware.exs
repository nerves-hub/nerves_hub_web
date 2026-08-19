defmodule NervesHub.Repo.Migrations.AllowUnsignedFirmware do
  @moduledoc """
  Allow firmware to be stored without a signing key.

  Every firmware NervesHub accepted until now was an fwup archive, which is
  verified against an org's Ed25519 key before it is stored — so `org_key_id`
  could never be null. ESP-IDF images carry a Secure Boot v2 signature block
  instead, which `org_keys` cannot represent yet, so they are stored unsigned.

  The Ecto schema has always listed `org_key_id` as optional; this brings the
  database in line with it.
  """

  use Ecto.Migration

  # Raw SQL rather than `modify/3`: Ecto's `modify` always emits an
  # `ALTER COLUMN ... TYPE` clause, which restates the column type and takes
  # ACCESS EXCLUSIVE even when the type is unchanged. `20180618143235` declared
  # this column `:bigint` while it is `integer` on current databases, so naming
  # a type here risks silently narrowing the FK on some deployment. Dropping the
  # constraint alone is a catalog-only change and cannot touch the type.
  def up() do
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id DROP NOT NULL")

    # Dropping NOT NULL alone would widen "every firmware is signed" from an
    # invariant the database held to one only `Fwup.verify_signature/2` holds.
    # This keeps the 2018 guarantee exactly where it was for fwup and opens it
    # only for the format that cannot be verified yet.
    #
    # `IS NOT DISTINCT FROM` rather than `=` because `tool` is nullable: with
    # `=`, a NULL tool would make the whole expression NULL, which a CHECK
    # treats as passing, so an unsigned row with no tool would slip through.
    execute("""
    ALTER TABLE firmwares
      ADD CONSTRAINT firmwares_signed_unless_esp_idf
      CHECK (org_key_id IS NOT NULL OR tool IS NOT DISTINCT FROM 'esp-idf')
    """)
  end

  def down() do
    execute("ALTER TABLE firmwares DROP CONSTRAINT firmwares_signed_unless_esp_idf")

    # Fails while any unsigned firmware exists — those rows would have to be
    # removed first. In practice this is a one-way door; see
    # docs/esp_idf_support.md.
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id SET NOT NULL")
  end
end
