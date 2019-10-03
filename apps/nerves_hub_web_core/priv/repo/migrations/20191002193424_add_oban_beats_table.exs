defmodule NervesHubWebCore.Repo.Migrations.AddObanBeatsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 3)
  end

  def down do
    Oban.Migrations.down(version: 2)
  end
end
