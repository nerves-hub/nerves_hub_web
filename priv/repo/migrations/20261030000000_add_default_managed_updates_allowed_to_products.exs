defmodule NervesHub.Repo.Migrations.AddDefaultManagedUpdatesAllowedToProducts do
  @moduledoc """
  The `managed_updates_allowed` grant a product's new devices start with.

  The grant itself stays on the device, and this is only where it starts: a
  device created in the product takes the product's value unless whoever
  created it said otherwise, and changing this later moves no existing device.

  Defaults to `false`, so a product keeps opting its devices in, as before,
  until someone decides its devices should arrive able to manage themselves.
  """

  use Ecto.Migration

  def change() do
    alter table(:products) do
      add(:default_managed_updates_allowed, :boolean, null: false, default: false)
    end
  end
end
