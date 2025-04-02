defmodule NervesHub.Repo.Migrations.AddLatestConnectionIdToDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      add(:latest_connection_id, :binary_id)
    end
  end
end
