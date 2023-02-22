defmodule NervesHubWebCore.Repo.Migrations.AddUpdateTrackingToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:update_attempts, {:array, :utc_datetime})
    end
  end
end
