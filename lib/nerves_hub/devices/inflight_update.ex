defmodule NervesHub.Devices.InflightUpdate do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.Firmware

  @required_params [:device_id, :deployment_id, :firmware_id, :firmware_uuid, :expires_at]

  schema "inflight_updates" do
    belongs_to(:device, Device)
    belongs_to(:deployment, Deployment)
    belongs_to(:firmware, Firmware)

    field(:firmware_uuid, Ecto.UUID)
    field(:status, :string, default: "pending")
    field(:expires_at, :utc_datetime)

    timestamps(updated_at: false)
  end

  def create_changeset(params) do
    %InflightUpdate{}
    |> cast(params, @required_params)
    |> validate_required(@required_params)
    |> unique_constraint(:deployment_id,
      name: :inflight_updates_device_id_deployment_id_index
    )
  end
end
