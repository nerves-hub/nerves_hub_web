defmodule NervesHub.Repo.Migrations.AddDisplayPreferencesToUser do
  use Ecto.Migration

  def change() do
    alter table(:users) do
      add(:display_preferences, :map)
    end
  end
end
