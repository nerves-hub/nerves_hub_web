defmodule NervesHub.Repo.Migrations.ChangeDeviceConnections do
  use Ecto.Migration

  def change() do
    create table(:latest_device_connections, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:device_id, references(:devices, on_delete: :delete_all), null: false)
      add(:status, :string)
      add(:established_at, :utc_datetime_usec)
      add(:last_seen_at, :utc_datetime_usec)
      add(:disconnected_at, :utc_datetime_usec)
      add(:disconnected_reason, :text)
      add(:metadata, :map, default: %{})
    end

    create(unique_index(:latest_device_connections, [:device_id]))

    create(index(:latest_device_connections, [:device_id, asc: :established_at]))
  end
end
