defmodule NervesHub.Devices.DeviceMessages do
  @moduledoc """
  A record of every message that crossed a device's websocket.

  Devices and the platform talk over three channels — the device channel, the
  console, and extensions — and until now none of that traffic was kept. When a
  device did not do what it was told, there was no way to answer the first
  question worth asking: was it ever told? This answers it, for both directions.

  ## What is recorded

  Every message carries its direction (`received` from the device, `sent` to
  it), the channel it crossed, the event name, and when. What is kept of the
  body depends on the channel:

    * **device** and **extensions** — the payload, redacted and capped by
      `NervesHub.Devices.DeviceMessages.Payload`.
    * **console** — the size only, never the contents. Console traffic is raw
      terminal I/O: it is what a person typed at a prompt and what came back,
      which routinely includes credentials. Its volume is also unlike the
      others — a single command is dozens of messages — so recording bodies
      would dominate the table while being the part least safe to keep.

  ## Where recording happens

  At the connection boundary, in the channels themselves, so a message is
  recorded because it actually crossed the wire rather than because something
  intended it to. The exception is the platform's fastlaned sends — `identify`,
  `reboot`, `update`, `archive` and the public key messages — which Phoenix
  pushes straight from the broadcast to the transport without the channel
  process ever seeing them. Those are recorded where they are broadcast, which
  for them is the same thing.

  Writes go through `NervesHub.Analytics.Buffer`, the same batching path device
  connection events and log lines use, and are never waited on. This is the
  highest-volume of the three — every message on every channel, including
  per-keystroke console traffic — so a row-at-a-time write pattern was never an
  option. If analytics is not configured, recording is a no-op.

  ## Live updates

  Storage is batched, but the Data History tab is not made to wait for a batch:
  every recorded message is also broadcast on the device's internal topic as it
  happens, and the tab streams what it receives. The two paths are independent —
  a message shows up live whether or not its batch has been written yet, and a
  dropped batch costs the history, not the live view.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages.Payload
  alias NervesHub.Devices.PubSub

  @type direction() :: DeviceMessage.direction()
  @type topic() :: DeviceMessage.topic()

  @doc """
  Records a message and its payload.

  Used for the device and extensions channels. Returns `:ok` regardless of
  whether the row is written — see `Buffer`.
  """
  @spec record(DeviceInfo.t() | Device.t(), direction(), topic(), String.t(), term()) :: :ok
  def record(device, direction, topic, event, payload) do
    if enabled?() do
      {encoded, size, truncated?} = Payload.encode(payload)

      device
      |> base_row(direction, topic, event)
      |> Map.merge(%{payload: encoded, payload_bytes: size, truncated: (truncated? && 1) || 0})
      |> insert(device)
    end

    :ok
  end

  @doc """
  The topic a device's messages are broadcast on as they are recorded.
  """
  @spec topic(pos_integer()) :: String.t()
  def topic(device_id), do: "internal:device:#{device_id}"

  @doc """
  The event name carried by a live message broadcast.
  """
  @spec broadcast_event() :: String.t()
  def broadcast_event(), do: "device_message:recorded"

  @doc """
  Records that a message crossed, and how large it was, but not its contents.

  Used for the console, where the contents are neither safe to keep nor useful
  in bulk. `data` is the raw terminal payload; only its size is read.
  """
  @spec record_size_only(DeviceInfo.t() | Device.t(), direction(), topic(), String.t(), term()) :: :ok
  def record_size_only(device, direction, topic, event, data) do
    if enabled?() do
      device
      |> base_row(direction, topic, event)
      |> Map.put(:payload_bytes, data_size(data))
      |> insert(device)
    end

    :ok
  end

  @doc """
  The most recent messages for a device, newest first.

  ## Options

    * `:limit` — how many to return, defaults to 100
    * `:direction` — `"received"` or `"sent"`
    * `:topic` — `"device"`, `"console"` or `"extensions"`

  """
  @spec recent(Device.t(), keyword()) :: [DeviceMessage.t()]
  def recent(device, opts \\ []) do
    DeviceMessage
    |> where(product_id: ^device.product_id)
    |> where(device_id: ^device.id)
    |> filter_by(:direction, opts[:direction])
    |> filter_by(:topic, opts[:topic])
    |> order_by(desc: :timestamp)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> AnalyticsRepo.all()
  end

  @doc "Whether device messages are being recorded on this node."
  @spec enabled?() :: boolean()
  def enabled?(), do: Application.get_env(:nerves_hub, :analytics_enabled, false)

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, _field, ""), do: query
  defp filter_by(query, :direction, value), do: where(query, direction: ^value)
  defp filter_by(query, :topic, value), do: where(query, topic: ^value)

  defp base_row(device, direction, topic, event) do
    %{
      timestamp: DateTime.utc_now(),
      org_id: org_id(device),
      product_id: product_id(device),
      device_id: device_id(device),
      direction: to_string(direction),
      topic: to_string(topic),
      event: to_string(event),
      payload: "",
      payload_bytes: 0,
      truncated: 0
    }
  end

  defp insert(row, device) do
    :ok = Buffer.insert(DeviceMessage, DeviceMessage.changeset(row))
    :ok = broadcast(device_id(device), row)
  end

  # Sent as the schema struct rather than the raw row so the tab renders a live
  # message exactly as it renders one read back from ClickHouse.
  defp broadcast(device_id, row) do
    PubSub.broadcast(device_id, broadcast_event(), struct!(DeviceMessage, row))
  end

  defp device_id(%DeviceInfo{device_id: id}), do: id
  defp device_id(%Device{id: id}), do: id

  defp org_id(%DeviceInfo{org_id: id}), do: id
  defp org_id(%Device{org_id: id}), do: id

  defp product_id(%DeviceInfo{product_id: id}), do: id
  defp product_id(%Device{product_id: id}), do: id

  # Console payloads are `%{"data" => binary}`, but a device can send a shape
  # that is not that, and a malformed console frame is not worth losing the
  # row over.
  defp data_size(%{"data" => data}) when is_binary(data), do: byte_size(data)
  defp data_size(data) when is_binary(data), do: byte_size(data)
  defp data_size(data), do: data |> inspect() |> byte_size()
end
