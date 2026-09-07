defmodule NervesHub.Repo.Migrations.AllowUnsignedFirmware do
  @moduledoc """
  Allow an ESP-IDF firmware to be stored without a signing key.

  Every other firmware must still have one. The rule is "signed unless it is an
  ESP-IDF image whose product allows otherwise", and the half of that which can
  be expressed here is enforced here.

  `IS NOT DISTINCT FROM` rather than `=`: `tool` is nullable, and a CHECK passes
  when its expression is NULL.
  """

  use Ecto.Migration

  def up() do
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id DROP NOT NULL")

    execute("""
    ALTER TABLE firmwares
      ADD CONSTRAINT firmwares_signed_unless_esp_idf
      CHECK (org_key_id IS NOT NULL OR tool IS NOT DISTINCT FROM 'esp-idf')
    """)
  end

  def down() do
    execute("ALTER TABLE firmwares DROP CONSTRAINT firmwares_signed_unless_esp_idf")
    execute("ALTER TABLE firmwares ALTER COLUMN org_key_id SET NOT NULL")
  end
end
