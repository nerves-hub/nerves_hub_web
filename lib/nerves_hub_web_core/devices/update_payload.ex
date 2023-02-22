defmodule NervesHubWebCore.Devices.UpdatePayload do
  @moduledoc """
  This struct represents the payload that gets dispatched to devices
  """

  alias NervesHubWebCore.Firmwares.FirmwareMetadata
  alias NervesHubWebCore.Deployments.Deployment

  @derive {Jason.Encoder,
           only: [
             :update_available,
             :firmware_url,
             :firmware_meta,
             :deployment_id
           ]}

  defstruct update_available: false,
            firmware_url: nil,
            firmware_meta: nil,
            deployment: nil,
            deployment_id: nil

  @type t ::
          %__MODULE__{
            update_available: false,
            firmware_meta: nil,
            firmware_url: nil,
            deployment: nil,
            deployment_id: nil
          }
          | %__MODULE__{
              update_available: true,
              firmware_meta: FirmwareMetadata.t(),
              firmware_url: String.t(),
              deployment: Deployment.t(),
              deployment_id: non_neg_integer()
            }
end
