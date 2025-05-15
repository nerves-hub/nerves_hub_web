defmodule NervesHub.Repo.Migrations.AddFirstInLineUpdatesToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:first_in_line_for_updates, :boolean, default: false, null: false)
    end
  end
end
