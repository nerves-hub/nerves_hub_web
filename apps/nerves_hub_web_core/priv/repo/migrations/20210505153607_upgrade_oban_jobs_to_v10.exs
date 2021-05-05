defmodule NervesHubWebCore.Repo.Migrations.UpgradeObanJobsToV10 do
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 10)
  def down, do: Oban.Migrations.down()
end
