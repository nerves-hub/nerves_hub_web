defmodule NervesHub.Repo.Migrations.RemoveTtlFromFirmwares do
  use Ecto.Migration

  def up do
    alter table(:firmwares) do
      remove(:ttl)
      remove(:ttl_until)
    end
  end

  def down do
    raise "One way migration"
  end
end
