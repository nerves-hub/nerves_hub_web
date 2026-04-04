defmodule NervesHub.Repo.Migrations.AddChecksumsToFirmwares do
  use Ecto.Migration

  def change() do
    alter table(:firmwares) do
      add(:checksum, :string, null: true)
      add(:partials_checksums, {:array, :string}, default: [], null: false)
    end
  end
end
