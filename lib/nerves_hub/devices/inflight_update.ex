defmodule NervesHub.Devices.InflightUpdate do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @type t :: %__MODULE__{}
  @required_params [:device_id, :deployment_id, :firmware_id, :firmware_uuid, :expires_at]
  @optional_params [:priority_queue]

  schema "inflight_updates" do
    belongs_to(:device, Device)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)
    belongs_to(:firmware, Firmware)

    field(:firmware_uuid, Ecto.UUID)
    field(:status, :string, default: "pending")
    field(:expires_at, :utc_datetime)
    field(:priority_queue, :boolean, default: false)

    timestamps(updated_at: false)
  end

  def create_changeset(params) do
    %InflightUpdate{}
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:deployment_id,
      name: :inflight_updates_device_id_deployment_id_index
    )
  end

  def update_status_changeset(inflight_update, status) do
    inflight_update
    |> change()
    |> put_change(:status, status)
    |> validate_required(@required_params)
  end
end
