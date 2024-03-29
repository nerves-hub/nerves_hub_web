defmodule NervesHub.Repo.Migrations.AddFirmwareTtlOrgLimit do
  use Ecto.Migration

  def change do
    alter table(:org_limits) do
      add(:firmware_ttl_seconds, :integer)
      add(:firmware_ttl_seconds_default, :integer)
    end

    alter table(:firmwares) do
      add(:ttl, :integer, null: false, default: 604_800)
      add(:ttl_until, :utc_datetime)
    end
  end
end
