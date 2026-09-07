defmodule NervesHub.Repo.Migrations.AddSchemeToOrgKeys do
  @moduledoc """
  Record which signature scheme an organization key belongs to.

  Until now every key was an fwup Ed25519 public key, so the column is
  backfilled to `ed25519` and the schema keeps that as the default. ESP-IDF
  Secure Boot v2 uses RSA-3072, which the Ed25519 format check would reject —
  the two cannot share a validation without knowing which is which.

  `key` also has to widen: it is `varchar(255)`, which fits a 44 character
  base64 Ed25519 key but not a ~625 byte RSA-3072 PEM.
  """

  use Ecto.Migration

  def up() do
    alter table(:org_keys) do
      add(:scheme, :string, null: false, default: "ed25519")
    end

    # varchar(255) -> text is binary-coercible in Postgres, so no table rewrite.
    execute("ALTER TABLE org_keys ALTER COLUMN key TYPE text")
  end

  def down() do
    # Will fail if any key longer than 255 characters has been registered.
    execute("ALTER TABLE org_keys ALTER COLUMN key TYPE varchar(255)")

    alter table(:org_keys) do
      remove(:scheme)
    end
  end
end
