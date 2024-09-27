defmodule NervesHub.Repo.Migrations.CreateDeviceConnection do
  use Ecto.Migration

  def change do
    create table(:device_connections, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:device_id, references(:devices), null: false)
      add(:status, :string)
      add(:established_at, :utc_datetime)
      add(:last_seen_at, :utc_datetime)
      add(:disconnected_at, :utc_datetime)
      add(:disconnected_reason, :text)
      add(:metadata, :map, default: %{})
    end

    create(index(:device_connections, [:device_id, :established_at]))
    create(index(:device_connections, [:device_id, :status]))
  end
end
