defmodule NervesHubWebCore.Repo.Migrations.AddRateAndThresholdsToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:device_failure_threshold, :integer, default: 3)
      add(:device_failure_rate_seconds, :integer, default: 180)
      add(:device_failure_rate_amount, :integer, default: 5)

      add(:failure_threshold, :integer, default: 50)
      add(:failure_rate_seconds, :integer, default: 300)
      add(:failure_rate_amount, :integer, default: 5)

      add(:healthy, :boolean, default: true)
    end
  end
end
