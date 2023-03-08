defmodule NervesHub.Repo.Migrations.AddAutomaticDeploymentsBlockedUntilToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:updates_blocked_until, :utc_datetime)
    end
  end
end
