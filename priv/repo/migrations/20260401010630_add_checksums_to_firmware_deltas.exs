defmodule NervesHub.Repo.Migrations.AddChecksumsToFirmwareDeltas do
  use Ecto.Migration

  def change() do
    alter table(:firmware_deltas) do
      add(:checksum, :string, null: true)
      add(:partials_checksums, {:array, :string}, default: [], null: false)
    end
  end
end
