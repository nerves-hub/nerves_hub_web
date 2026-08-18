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

  def up() do
    alter table(:firmwares) do
      modify(:org_key_id, :integer, null: true)
    end
  end

  def down() do
    # Irreversible while unsigned firmware exists — those rows would have to be
    # deleted before the constraint could be restored.
    alter table(:firmwares) do
      modify(:org_key_id, :integer, null: false)
    end
  end
end
