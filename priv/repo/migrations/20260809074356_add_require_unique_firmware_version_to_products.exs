defmodule NervesHub.Repo.Migrations.AddRequireUniqueFirmwareVersionToProducts do
  use Ecto.Migration

  # When on, uploading firmware whose version already exists for the product
  # (same platform + architecture) is rejected.
  #
  # DB default is `false` so all *existing* products keep the current behaviour
  # (off). New products default to `true` via the schema field default, which is
  # what gets inserted for records created through `Product.changeset/2`.
  def change() do
    alter table(:products) do
      add(:require_unique_firmware_version, :boolean, default: false, null: false)
    end
  end
end
