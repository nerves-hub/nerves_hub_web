defmodule NervesHub.Repo.Migrations.AddReleaseNetworkInterfacesToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :release_network_interfaces, {:array, :string}, default: [], null: false
    end
  end
end
