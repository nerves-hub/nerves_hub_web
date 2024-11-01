defmodule NervesHub.Repo.Migrations.CreateDeviceMetrics do
  use Ecto.Migration

  def change do
    create table(:device_metrics) do
      add(:device_id, references(:devices), null: false)
      add(:key, :string)
      add(:value, :float)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:device_metrics, [:device_id, :inserted_at])
    create index(:device_metrics, [:key, :inserted_at])
    create index(:device_metrics, [:inserted_at])
  end
end
