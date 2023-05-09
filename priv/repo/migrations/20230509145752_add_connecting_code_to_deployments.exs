defmodule NervesHub.Repo.Migrations.AddConnectingCodeToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:connecting_code, :text)
    end
  end
end
