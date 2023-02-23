defmodule NervesHub.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  # defdelegate up, to: Oban.Migrations
  # defdelegate down, to: Oban.Migrations

  def up() do
    Oban.Migrations.up()
    create_if_not_exists unique_index(:oban_jobs, [:args, :scheduled_at, :worker])
  end

  def down() do
    drop_if_exists unique_index(:oban_jobs, [:args, :scheduled_at, :worker])
    Oban.Migrations.down()
  end
end
