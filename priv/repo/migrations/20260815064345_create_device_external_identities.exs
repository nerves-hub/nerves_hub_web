defmodule NervesHub.Repo.Migrations.CreateDeviceExternalIdentities do
  use Ecto.Migration

  def change() do
    create table(:device_external_identities) do
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)

      add(:service, :string, null: false)

      # Which endpoint of that service this is. A device can run two iroh
      # endpoints — a console and an application, say — each holding its own key.
      #
      # NOT NULL with a default is load bearing: a nullable column silently
      # defeats the unique index below, because NULL != NULL in Postgres, so the
      # duplicates it exists to prevent would insert without any error.
      add(:instance, :string, null: false, default: "default")

      add(:identifier, :string, null: false)
      add(:details, :map, null: false, default: %{})
      add(:source, :string, null: false, default: "device_reported")
      add(:last_reported_at, :utc_datetime)

      timestamps()
    end

    # A device has at most one identity per service per instance.
    create(unique_index(:device_external_identities, [:device_id, :service, :instance]))

    # And no two devices may claim the same key — this is what surfaces a cloned
    # SD card, where a whole batch boots holding the identity of the device that
    # was imaged.
    create(unique_index(:device_external_identities, [:service, :identifier]))
  end
end
