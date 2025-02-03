defmodule NervesHub.Repo.Migrations.AddLatestHealthIdToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:latest_health_id, :integer)
    end
  end
end
