defmodule NervesHub.Devices.PinnedDevice do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.PinnedDevice

  @type t :: %__MODULE__{}

  @required [:user_id, :device_id]
  schema "pinned_devices" do
    belongs_to(:user, User)
    belongs_to(:device, Device)

    timestamps(updated_at: false)
  end

  def create(params \\ %{}) do
    %PinnedDevice{}
    |> cast(params, @required)
    |> validate_required(@required)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:device_id)
  end
end
