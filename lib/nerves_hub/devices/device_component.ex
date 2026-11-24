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
  and comes back as the same component if the device lists it again. Only a
  person forgetting it deletes it.

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
    field(:firmware_version, :string)
    field(:address, :string)

    field(:reachable, :boolean, default: true)
    field(:listed, :boolean, default: true)

    field(:last_seen_at, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)
    field(:missing_since, :utc_datetime_usec)

    # `readings` is `%{name => %{"value" => number, "at" => ISO 8601}}`,
    # `state` is `%{name => %{"value" => string, "since" => ISO 8601, "detail" => string | nil}}`.
    # Neither changes `status/1`.
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
