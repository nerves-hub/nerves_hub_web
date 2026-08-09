defmodule NervesHub.Repo.Migrations.AddRequireUniqueFirmwareVersionToProducts do
  use Ecto.Migration

  # Product setting: when on, uploaded firmware must have a version not already
  # used by another firmware for the same platform/architecture in the product.
  #
  # The column default is `false` so existing products are unaffected (opt-out).
  # New products default to `true` via the schema field default in
  # NervesHub.Products.Product, so the setting is on for products created from
  # now on.
  def change() do
    alter table(:products) do
      add(:require_unique_firmware_version, :boolean, null: false, default: false)
    end
  end
end
