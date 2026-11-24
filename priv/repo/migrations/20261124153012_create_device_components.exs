defmodule NervesHub.Repo.Migrations.CreateDeviceComponents do
  use Ecto.Migration

  def change() do
    # What each device is connected to, as its latest `components` snapshot
    # said. One row per component per device. A component the device stops
    # listing keeps its row, marked unlisted, until somebody forgets it; the
    # transitions live in ClickHouse as `device_component_history`.
    create table(:device_components) do
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)

      # Denormalised from the device, as `device_alarms` does: the product's
      # Components page groups every component in the product by model, and
      # the write path has the product to hand on `DeviceInfo`.
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      # Identity: `namespace` and `serial` say which component this is on the
      # device; `namespace`, `vendor` and `model` say what model it is. See
      # docs/components.md for how each namespace fills them in.
      add(:namespace, :string, null: false)
      add(:vendor, :string, null: false)
      add(:model, :string, null: false)
      add(:serial, :string, null: false)

      add(:name, :string)
      add(:vendor_name, :string)
      add(:model_name, :string)
      add(:hardware_revision, :string)
      add(:firmware_version, :string)
      add(:address, :string)

      # `reachable` is the device's word. `listed` is whether the latest
      # snapshot had the component at all. Missing is either being false.
      add(:reachable, :boolean, null: false, default: true)
      add(:listed, :boolean, null: false, default: true)

      # When the device last heard from it, by the device's clock where that
      # was believable and otherwise when a snapshot listed it reachable.
      add(:last_seen_at, :utc_datetime_usec)

      add(:first_seen_at, :utc_datetime_usec, null: false)

      # Set when the component went missing, cleared when it came back.
      add(:missing_since, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    # The snapshot upsert's target, and every read of one device's components.
    create(unique_index(:device_components, [:device_id, :namespace, :serial]))

    # The product's Components page, grouped by model.
    create(index(:device_components, [:product_id, :namespace, :vendor, :model]))
  end
end
