defmodule NervesHub.Repo.Migrations.AddUpdateToolSettingsToProducts do
  @moduledoc """
  Let an organization decide, per product, which firmware formats it accepts.

  `allowed_update_tools` defaults to `{fwup}`, so every existing product keeps
  behaving exactly as it did and no product accepts a new format until someone
  opts it in.

  `allow_unsigned_esp_idf_firmware` is the escape hatch for the common case that
  an ESP-IDF build is simply not signed. It is deliberately ESP-specific rather
  than a general `allow_unsigned_firmware`: fwup archives are always verified,
  and a general name would read as though that could be turned off.
  """

  use Ecto.Migration

  def up() do
    alter table(:products) do
      add(:allowed_update_tools, {:array, :string}, null: false, default: ["fwup"])
      add(:allow_unsigned_esp_idf_firmware, :boolean, null: false, default: false)
    end

    # Unsigned firmware is possible again, so `org_key_id` cannot be NOT NULL.
    # The CHECK keeps the 2018 guarantee for fwup, which is never unsigned
    # whatever a product setting says — the per-product rule lives in `products`
    # and cannot be expressed here.
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

    alter table(:products) do
      remove(:allow_unsigned_esp_idf_firmware)
      remove(:allowed_update_tools)
    end
  end
end
