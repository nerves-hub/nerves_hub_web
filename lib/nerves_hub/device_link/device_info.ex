defmodule NervesHub.DeviceLink.DeviceInfo do
  @moduledoc """
  What the platform and a device's connection both need to know about the device.

  Deliberately flat and small: ids, flags, a timestamp and a metadata map, with
  no Ecto structs and nothing lazily loaded. It travels with every call, and it
  has to mean the same thing on both ends — so this module's name is part of the
  contract, not an implementation detail. A copy of it living anywhere else must
  keep this name, or a struct sent from there will not match `%DeviceInfo{}`
  here.

  `device_updates_enabled` is superseded by `device_update_mode` and is still
  populated so that a node running the previous release, which does not know the
  new key, keeps working through a rolling deploy. It is removed in the next
  release; read `device_update_mode` instead.
  """

  alias OpenTelemetry.Tracer

  defstruct [
    :allowed_extensions,
    :connection_ref,
    :deployment_id,
    :device_id,
    :device_identifier,
    :device_network_interface,
    :device_update_mode,
    :device_updates_blocked_until,
    :device_updates_enabled,
    :firmware_metadata,
    :managed_updates_allowed,
    :org_id,
    :product_id
  ]

  @type t :: %__MODULE__{
          allowed_extensions: list(atom()) | nil,
          connection_ref: String.t() | nil,
          deployment_id: pos_integer() | nil,
          device_id: pos_integer() | nil,
          device_update_mode: :off | :automatic | :device_managed | nil,
          managed_updates_allowed: boolean() | nil,
          device_updates_enabled: boolean() | nil,
          device_updates_blocked_until: DateTime.t() | nil,
          device_identifier: String.t() | nil,
          device_network_interface: String.t() | nil,
          firmware_metadata: map() | nil,
          org_id: pos_integer() | nil,
          product_id: pos_integer() | nil
        }

  @doc """
  The device's ids, as attributes for a span about it, so its traces can be
  found by device, product or organization.

  Ids only. A device's identifier is often its serial number.
  """
  @spec trace_attributes(t()) :: %{atom() => pos_integer()}
  def trace_attributes(%__MODULE__{} = device_info) do
    %{
      "nerves_hub.device.id": device_info.device_id,
      "nerves_hub.product.id": device_info.product_id,
      "nerves_hub.org.id": device_info.org_id
    }
    |> Map.reject(fn {_key, id} -> is_nil(id) end)
  end

  @doc """
  Puts the device's ids on the current span, with any `attributes` saying what
  the span is about, such as the event a device sent.

  The device and extensions channels both call it, so their spans are tagged
  alike.
  """
  @spec set_span_attributes(t(), map()) :: :ok
  def set_span_attributes(%__MODULE__{} = device_info, attributes \\ %{}) do
    _ = device_info |> trace_attributes() |> Map.merge(attributes) |> Tracer.set_attributes()
    :ok
  end
end
