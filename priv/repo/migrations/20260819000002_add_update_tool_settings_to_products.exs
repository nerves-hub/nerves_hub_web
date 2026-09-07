defmodule NervesHub.Repo.Migrations.AddUpdateToolSettingsToProducts do
  @moduledoc """
  Per-product control over which firmware formats a product accepts.

  `allowed_update_tools` defaults to `{fwup}`, so a product accepts a new
  format only once someone opts it in.

  `allow_unsigned_esp_idf_firmware` allows an ESP-IDF image with no Secure Boot
  v2 signature block. It is ESP-specific rather than a general
  `allow_unsigned_firmware` because fwup archives are always verified.
  """

  use Ecto.Migration

  def change() do
    alter table(:products) do
      add(:allowed_update_tools, {:array, :string}, null: false, default: ["fwup"])
      add(:allow_unsigned_esp_idf_firmware, :boolean, null: false, default: false)
    end
  end
end
