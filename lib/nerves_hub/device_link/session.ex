defmodule NervesHub.DeviceLink.Session do
  @moduledoc """
  Everything `NervesHub.DeviceLink` remembers about one device's link between
  messages.

  Held by whoever owns the connection and handed back on every call, rather than
  living in a process next to the platform. That is what lets the connection
  outlive the platform node that last serviced it: there is no session process to
  die, and nothing to rebuild.

  Keep this small and plainly serialisable — it travels with every call once
  dispatch is remote.
  """

  alias NervesHub.DeviceLink.DeviceInfo

  defstruct [
    :currently_downloading_uuid,
    :deployment_topic,
    :device_api_version,
    :device_info,
    script_refs: %{}
  ]

  @type t() :: %__MODULE__{
          device_info: DeviceInfo.t(),
          device_api_version: String.t() | nil,
          currently_downloading_uuid: String.t() | nil,
          deployment_topic: String.t() | nil,
          script_refs: %{String.t() => pid()}
        }
end
