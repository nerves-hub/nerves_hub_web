defmodule NervesHub.Repo.Migrations.RequireSignedFirmware do
  @moduledoc """
  Restore `firmwares.org_key_id` to NOT NULL.

  `20260818000000` made it nullable so ESP-IDF images could be stored unsigned,
  because nothing could verify a Secure Boot v2 signature at the time.
  `20260819000000` fixed that, and ESP-IDF images are now required to be signed
  exactly as fwup archives are — so no firmware can be unsigned and the
  accommodation, along with the CHECK that scoped it, is no longer needed.

  These three migrations cancel out and are worth collapsing before this lands.
  They are kept separate so the reasoning survives in the history.
  """

  use Ecto.Migration

  def up() do
    execute("ALTER TABLE firmwares DROP CONSTRAINT firmwares_signed_unless_esp_idf")
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id SET NOT NULL")
  end

  def down() do
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id DROP NOT NULL")

    execute("""
    ALTER TABLE firmwares
      ADD CONSTRAINT firmwares_signed_unless_esp_idf
      CHECK (org_key_id IS NOT NULL OR tool IS NOT DISTINCT FROM 'esp-idf')
    """)
  end
end
