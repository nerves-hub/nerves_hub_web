defmodule NervesHub.Repo.Migrations.AddRateAndThresholdsToDeploymentsTemporarily do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:failure_rate_seconds, :integer, default: 300)
      add(:failure_rate_amount, :integer, default: 5)
    end
  end
end
