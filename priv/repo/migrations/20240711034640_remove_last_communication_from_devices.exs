defmodule NervesHub.Repo.Migrations.RemoveLastCommunicationFromDevices do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      remove :last_communication, :utc_datetime
    end
  end

  def down do
    raise "One way migration"
  end
end
