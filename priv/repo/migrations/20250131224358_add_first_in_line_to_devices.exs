defmodule NervesHub.Repo.Migrations.AddFirstInLineToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:first_in_line, :boolean, default: false)
    end
  end
end
