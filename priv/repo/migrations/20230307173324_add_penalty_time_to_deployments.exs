defmodule NervesHub.Repo.Migrations.AddPenaltyTimeToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:penalty_timeout_minutes, :integer, default: 1440, null: false)
    end
  end
end
