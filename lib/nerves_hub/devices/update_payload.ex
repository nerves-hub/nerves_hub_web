defmodule NervesHub.Devices.UpdatePayload do
  @moduledoc """
  This struct represents the payload that gets dispatched to devices
  """

  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @derive {Jason.Encoder,
           only: [
             :update_available,
             :firmware_url,
             :firmware_meta,
             :size,
             :checksum,
             :partials_checksums,
             :deployment_id
           ]}

  defstruct checksum: nil,
            deployment_group: nil,
            deployment_id: nil,
            firmware_meta: nil,
            firmware_url: nil,
            partials_checksums: nil,
            size: nil,
            update_available: false

  @type t ::
          %__MODULE__{
            update_available: false,
            firmware_meta: nil,
            firmware_url: nil,
            size: nil,
            checksum: nil,
            partials_checksums: nil,
            deployment_group: nil,
            deployment_id: nil
          }
          | %__MODULE__{
              update_available: true,
              firmware_meta: FirmwareMetadata.t(),
              firmware_url: String.t(),
              size: non_neg_integer(),
              checksum: String.t(),
              partials_checksums: [String.t()],
              deployment_group: DeploymentGroup.t(),
              deployment_id: non_neg_integer()
            }
end
