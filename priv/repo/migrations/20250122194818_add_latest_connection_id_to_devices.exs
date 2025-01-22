defmodule NervesHub.Repo.Migrations.AddLatestConnectionIdToDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      add(:latest_connection_id, references(:device_connections, type: :uuid))
    end
  end
end
