defmodule NervesHubWebCore.Repo.Migrations.AddDeleteRole do
  use Ecto.Migration
  @disable_ddl_transaction true

  def up do
    Ecto.Migration.execute "ALTER TYPE role ADD VALUE IF NOT EXISTS'delete'"
  end

  def down do
  end
end
