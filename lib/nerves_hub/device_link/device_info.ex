defmodule NervesHub.DeviceLink.DeviceInfo do
  @moduledoc """
  What the platform and a device's connection both need to know about the device.

  Deliberately flat and small: ids, flags, a timestamp and a metadata map, with
  no Ecto structs and nothing lazily loaded. It travels with every call, and it
  has to mean the same thing on both ends — so this module's name is part of the
  contract, not an implementation detail. A copy of it living anywhere else must
  keep this name, or a struct sent from there will not match `%DeviceInfo{}`
  here.
  """

  defstruct [
    :allowed_extensions,
    :connection_ref,
    :deployment_id,
    :device_id,
    :device_identifier,
    :device_network_interface,
    :device_updates_blocked_until,
    :device_updates_enabled,
    :firmware_metadata,
    :org_id,
    :product_id
  ]

  @type t :: %__MODULE__{
          allowed_extensions: list(atom()) | nil,
          connection_ref: String.t() | nil,
          deployment_id: pos_integer() | nil,
          device_id: pos_integer() | nil,
          device_updates_enabled: boolean() | nil,
          device_updates_blocked_until: DateTime.t() | nil,
          device_identifier: String.t() | nil,
          device_network_interface: String.t() | nil,
          firmware_metadata: map() | nil,
          org_id: pos_integer() | nil,
          product_id: pos_integer() | nil
        }
end
