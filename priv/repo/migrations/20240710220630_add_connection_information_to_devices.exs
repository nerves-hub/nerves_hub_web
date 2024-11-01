defmodule NervesHub.Repo.Migrations.AddConnectionInformationToDevices do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add(:connection_status, :string)
      add(:connection_established_at, :utc_datetime)
      add(:connection_disconnected_at, :utc_datetime)
      add(:connection_last_seen_at, :utc_datetime)
    end

    flush()

    execute("UPDATE devices SET connection_status = 'not_seen' WHERE last_communication IS NULL")
    execute("UPDATE devices SET connection_status = 'disconnected', connection_established_at = last_communication, connection_disconnected_at = last_communication, connection_last_seen_at = last_communication WHERE last_communication IS NOT NULL")
  end

  def down do
    raise "One way migration"
  end
end
