defmodule NervesHub.Repo.Migrations.AddStatusAndFirstSeenAtToDevices do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add(:status, :string)
      add(:first_seen_at, :utc_datetime)
    end

    flush()

    execute("UPDATE devices SET status = 'registered' WHERE connection_status = 'not_seen'")
    execute("UPDATE devices SET status = 'provisioned', first_seen_at = inserted_at WHERE connection_status != 'not_seen'")
  end

  def down do
    alter table(:devices) do
      remove(:status, :string)
      remove(:first_seen_at, :utc_datetime)
    end
  end
end
