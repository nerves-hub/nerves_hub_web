defmodule NervesHub.Repo.Migrations.AddConnectingCodeToDeploymentReleases do
  use Ecto.Migration

  def change() do
    alter table(:deployment_releases) do
      add(:connecting_code, :text)
      add(:connecting_code_mode, :string, null: false, default: "last")
    end
  end
end
