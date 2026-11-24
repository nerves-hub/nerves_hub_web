defmodule NervesHub.Devices.DeviceComponentHistory do
  @moduledoc """
  One change to one of a device's components: it appeared, went missing, came
  back, changed the version of something it holds, changed state, or was
  forgotten.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`. Where
  `NervesHub.Devices.DeviceComponent` is what a device has now, this is how it
  got there, and is what the Recent list on a component's panel reads. Only
  changes are written, so a device re-sending the same snapshot adds nothing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_component_history" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:namespace, Ch, type: "LowCardinality(String)")
    field(:serial, Ch, type: "String")

    # appeared, missing, returned, version_changed, forgotten or state_changed.
    field(:event, Ch, type: "LowCardinality(String)")

    # "unreachable" or "unlisted" for "missing"; the version moved from for
    # "version_changed"; empty otherwise.
    field(:detail, Ch, type: "String", default: "")

    # Which of `versions` moved, for "version_changed"; empty otherwise.
    field(:version_key, Ch, type: "LowCardinality(String)", default: "")

    # Every version the component reported at the time.
    field(:versions, Ch, type: "Map(LowCardinality(String), String)", default: %{})

    # For "state_changed": which state, and what it became. `detail` then holds
    # who or what changed it, where the device said.
    field(:state, Ch, type: "LowCardinality(String)", default: "")
    field(:value, Ch, type: "String", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch. Changes the struct
  directly rather than casting, as `DeviceAlarmHistory` does.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end
