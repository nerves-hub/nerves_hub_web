defmodule NervesHub.Repo.Migrations.FirmwareDeltasAddStatusField do
  use Ecto.Migration

  def up do
    alter table(:firmware_deltas) do
      add :status, :string
    end
    execute "UPDATE firmware_deltas SET status = 'completed'"
  end

  def down do
    alter table(:firmware_deltas) do
      remove :status, :string
    end
    execute "DELETE firmware_deltas WHERE status != 'completed'"
  end
end
