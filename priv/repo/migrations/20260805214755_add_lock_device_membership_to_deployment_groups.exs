defmodule NervesHub.Repo.Migrations.AddLockDeviceMembershipToDeploymentGroups do
  use Ecto.Migration

  def change() do
    alter table(:deployments) do
      add(:lock_device_membership, :boolean, default: false, null: false)
    end
  end
end
