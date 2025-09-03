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
             :deployment_id
           ]}

  defstruct deployment_group: nil,
            deployment_id: nil,
            firmware_meta: nil,
            firmware_url: nil,
            update_available: false

  @type t ::
          %__MODULE__{
            deployment_group: nil,
            deployment_id: nil,
            firmware_meta: nil,
            firmware_url: nil,
            update_available: false
          }
          | %__MODULE__{
              deployment_group: DeploymentGroup.t(),
              deployment_id: non_neg_integer(),
              firmware_meta: FirmwareMetadata.t(),
              firmware_url: String.t(),
              update_available: true
            }
end
