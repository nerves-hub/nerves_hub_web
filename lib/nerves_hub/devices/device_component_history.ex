defmodule NervesHub.Devices.DeviceComponentHistory do
  @moduledoc """
  One change to one of a device's components: it appeared, went missing, came
  back, changed firmware, or was forgotten.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`. Where
  `NervesHub.Devices.DeviceComponent` is what a device has now, this is how it
  got there, and is what the Recent list on a component's panel reads. Only
  changes are written, so a device re-sending the same snapshot adds nothing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @events ~w(appeared missing returned firmware_changed forgotten)

  @primary_key false
  schema "device_component_history" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:namespace, Ch, type: "LowCardinality(String)")
    field(:serial, Ch, type: "String")

    field(:event, Ch, type: "LowCardinality(String)")

    # "unreachable" or "unlisted" for "missing"; the version moved from for
    # "firmware_changed"; empty otherwise.
    field(:detail, Ch, type: "String", default: "")

    field(:firmware_version, Ch, type: "String", default: "")
  end

  @doc "Every event a row can record."
  @spec events() :: [String.t()]
  def events(), do: @events

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch. Changes the struct
  directly rather than casting, as `DeviceAlarmHistory` does.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end
