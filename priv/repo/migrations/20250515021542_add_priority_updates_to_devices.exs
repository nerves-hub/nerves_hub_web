defmodule NervesHub.Repo.Migrations.AddPriorityUpdatesToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:priority_updates, :boolean, default: false, null: false)
    end
  end
end
