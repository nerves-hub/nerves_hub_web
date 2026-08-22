defmodule NervesHub.Devices.DeviceMessage do
  @moduledoc """
  One message that crossed a device's websocket, in either direction.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer` and read back
  by the device's Data History tab.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type direction() :: :received | :sent
  @type topic() :: :device | :console | :extensions

  @type t :: %__MODULE__{}

  @directions ~w(received sent)
  @topics ~w(device console extensions)

  @primary_key false
  schema "device_messages" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    # "received" (device to platform) or "sent" (platform to device)
    field(:direction, Ch, type: "LowCardinality(String)")
    # which of the device's channels carried it: device, console, extensions
    field(:topic, Ch, type: "LowCardinality(String)")
    field(:event, Ch, type: "LowCardinality(String)")

    field(:payload, Ch, type: "String", default: "")
    field(:payload_bytes, Ch, type: "UInt32", default: 0)
    field(:truncated, Ch, type: "UInt8", default: 0)
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Every value here is supplied by the platform from what it already holds —
  none of it is user input — so this changes the struct directly rather than
  casting. The buffer flattens the changeset through the struct, which fills in
  the schema defaults for anything left unset; that matters because `insert_all`
  builds one statement per batch and every row has to carry the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)

  @doc "The directions a message can have."
  @spec directions() :: [String.t()]
  def directions(), do: @directions

  @doc "The topics a message can arrive on."
  @spec topics() :: [String.t()]
  def topics(), do: @topics

  @doc """
  True when the stored payload is only part of what was sent.

  See `NervesHub.Devices.DeviceMessages.Payload` for the cap.
  """
  @spec truncated?(t()) :: boolean()
  def truncated?(%__MODULE__{truncated: truncated}), do: truncated == 1

  @doc """
  True when only the size of the message was recorded, not its contents.

  Console traffic is raw terminal I/O and is recorded this way — see
  `NervesHub.Devices.DeviceMessages`.
  """
  @spec metadata_only?(t()) :: boolean()
  def metadata_only?(%__MODULE__{topic: "console"}), do: true
  def metadata_only?(%__MODULE__{}), do: false
end
