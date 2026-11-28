defmodule NervesHub.Devices.DeviceComponent do
  @moduledoc """
  One thing a device is connected to, as its `components` snapshots describe
  it: a microcontroller, a Zigbee or Z-Wave node, a USB peripheral.

  `namespace` and `serial` identify it on the device. `namespace`, `vendor` and
  `model` are its model, which the product's Components page groups by.
  docs/components.md is the contract that fills them in.

  A component is **missing** when the device says it can't reach it
  (`reachable: false`) or stops listing it (`listed: false`). Either way the row
  stays, so a sensor whose battery died keeps where it was and when it went,
  and comes back as the same component if the device lists it again. It is
  deleted when a person forgets it, or when the device stores more than 1,000
  and it is among those missing longest.

  Written only by `NervesHub.Devices.Components`, which compares each snapshot
  with these rows and records what changed.
  """

  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @type status() :: :working | :missing

  schema "device_components" do
    belongs_to(:device, Device)
    belongs_to(:product, Product)

    field(:namespace, :string)
    field(:vendor, :string)
    field(:model, :string)
    field(:serial, :string)

    field(:name, :string)
    field(:vendor_name, :string)
    field(:model_name, :string)
    field(:hardware_revision, :string)
    # What the component holds and which version of each, keyed by what it
    # is: `%{"firmware" => "2.2.1", "keypad_config" => "7"}`.
    field(:versions, :map, default: %{})
    field(:address, :string)

    field(:reachable, :boolean, default: true)
    field(:listed, :boolean, default: true)

    field(:last_seen_at, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)
    field(:missing_since, :utc_datetime_usec)

    # `readings` is `%{name => %{"value" => number, "at" => ISO 8601}}`,
    # `state` is `%{name => %{"value" => string, "since" => ISO 8601, "detail" => string | nil}}`,
    # plus `"snapshot" => true` where a snapshot set the value: its `since` is
    # the platform's clock, so any change replaces it. Neither changes `status/1`.
    field(:readings, :map, default: %{})
    field(:readings_at, :utc_datetime_usec)
    field(:state, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Working when the latest snapshot listed it as reachable, missing otherwise."
  @spec status(t()) :: status()
  def status(%__MODULE__{listed: true, reachable: true}), do: :working
  def status(%__MODULE__{}), do: :missing

  @doc """
  Why a missing component is missing: the device can't reach it, or stopped
  listing it. `nil` for a working one.
  """
  @spec missing_reason(t()) :: :unreachable | :unlisted | nil
  def missing_reason(%__MODULE__{listed: false}), do: :unlisted
  def missing_reason(%__MODULE__{reachable: false}), do: :unreachable
  def missing_reason(%__MODULE__{}), do: nil

  @doc "The firmware version the component reported, or `nil`."
  @spec firmware_version(t()) :: String.t() | nil
  def firmware_version(%__MODULE__{versions: versions}), do: Map.get(versions, "firmware")

  @doc """
  The versions other than firmware, as `{key, version}` pairs sorted by key:
  configuration, models and anything else the component holds.
  """
  @spec other_versions(t()) :: [{String.t(), String.t()}]
  def other_versions(%__MODULE__{versions: versions}), do: versions |> Map.delete("firmware") |> Enum.sort()

  @doc "A namespace as a person writes it: `zwave` is Z-Wave. Others as sent."
  @spec namespace_label(String.t()) :: String.t()
  def namespace_label("mcu"), do: "MCU"
  def namespace_label("zigbee"), do: "Zigbee"
  def namespace_label("zwave"), do: "Z-Wave"
  def namespace_label("ble"), do: "Bluetooth LE"
  def namespace_label("usb"), do: "USB"
  def namespace_label("custom"), do: "Custom"
  def namespace_label(namespace), do: namespace

  @doc "What to call it: the device's name for it, else the model's name, else the model."
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%__MODULE__{} = component), do: model_label(component)

  @doc """
  The model as a person reads it: "Sonoff SNZB-02D" where the component gave
  names, falling back to the identifiers.
  """
  @spec model_label(%{
          :vendor => String.t(),
          :model => String.t(),
          :vendor_name => String.t() | nil,
          :model_name => String.t() | nil,
          optional(atom()) => any()
        }) :: String.t()
  def model_label(%{vendor_name: vendor_name, model_name: model_name, vendor: vendor, model: model}) do
    [vendor_name || vendor, model_name || model]
    |> Enum.uniq()
    |> Enum.join(" ")
  end
end
