defmodule NervesHubWebCore.Repo.Migrations.AddFirmwarePerProductOrgLimit do
  use Ecto.Migration

  def change do
    alter table(:org_limits) do
      add(:firmware_per_product, :integer)
    end
  end
end
