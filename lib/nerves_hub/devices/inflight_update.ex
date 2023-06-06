defmodule NervesHub.Devices.InflightUpdate do
  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.Firmware

  schema "inflight_updates" do
    belongs_to(:device, Device)
    belongs_to(:deployment, Deployment)
    belongs_to(:firmware, Firmware)

    field(:firmware_uuid, Ecto.UUID)
    field(:status, :string, default: "pending")
    field(:expires_at, :utc_datetime)

    timestamps(updated_at: false)
  end
end
