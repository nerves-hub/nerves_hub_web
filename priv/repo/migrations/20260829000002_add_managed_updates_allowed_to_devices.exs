defmodule NervesHub.Repo.Migrations.AddManagedUpdatesAllowedToDevices do
  @moduledoc """
  Whether a device may put *itself* into `device_managed` update mode.

  `update_mode` is both a state and a capability, and the enum only carries the
  state. This is the capability: without it, any device could take itself out of
  its deployment group's rollout unasked.

  It gates device-initiated changes only. An operator setting `device_managed`
  from the dashboard is always allowed — the grant is about what a device may do
  to itself.

  Defaults to `false`, so self-management is something a fleet is opted into
  rather than something it starts with.
  """

  use Ecto.Migration

  def change() do
    alter table(:devices) do
      add(:managed_updates_allowed, :boolean, null: false, default: false)
    end
  end
end
