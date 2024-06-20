defmodule NervesHub.Repo.Migrations.CreateDeviceHealth do
  use Ecto.Migration

  def change do
    create table(:device_health) do
      add(:device_id, references(:devices), null: false)
      add(:data, :map)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:device_id_over_time, [:device_id, :created_at])
  end
end
