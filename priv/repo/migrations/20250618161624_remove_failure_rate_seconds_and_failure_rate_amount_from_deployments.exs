defmodule NervesHub.Repo.Migrations.RemoveFailureRateSecondsAndFailureRateAmountFromDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      remove :failure_rate_seconds
      remove :failure_rate_amount
    end
  end
end
