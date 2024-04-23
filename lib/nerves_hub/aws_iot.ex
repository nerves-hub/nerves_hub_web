defmodule NervesHub.AWSIoT do
  @moduledoc """
  Support for common AWS IOT infrastructure including MQTT and SQS

  Requires `:queues` to be defined in the application config or
  the supervisor is simply ignored

  See docs.nerves-hub.org for a general overview of the architecture
  """
  use Supervisor

  alias NervesHub.Tracker

  @type opt :: {:queues, [keyword()]}
  @spec start_link([opt]) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    opts =
      Application.get_env(:nerves_hub, __MODULE__, [])
      |> Keyword.merge(opts)

    case opts[:queues] do
      queues when is_list(queues) and length(queues) > 0 ->
        children =
          Enum.map(queues, &{__MODULE__.SQS, &1})
          |> maybe_add_local_broker(opts)

        Supervisor.init(children, strategy: :one_for_one)

      _ ->
        :ignore
    end
  end

  defp maybe_add_local_broker(children, opts) do
    if broker_spec = opts[:local_broker] do
      [broker_spec | children]
    else
      children
    end
  end

  if Application.compile_env(:nerves_hub, [__MODULE__, :local_broker], false) do
    def publish(serial, event, payload) do
      data = Jason.encode!(%{event: event, payload: payload})
      PintBroker.publish(__MODULE__.PintBroker, "nh/#{serial}", data)
    end
  else
    def publish(serial, event, payload) do
      # TODO: Topic and data may change soon
      # Stubbing out initial idea here for now
      data = %{event: event, payload: payload}
      topic = "/topics/nh/#{serial}"

      ExAws.Operation.JSON.new(:iot_data, %{path: topic, data: data})
      |> ExAws.request()
    end
  end

  defmodule SQS do
    @moduledoc """
    Consumer for AWS SQS messages

    This is the ingestion point of devices coming from the MQTT
    broker. A message from a device must include the `"identifier"`
    key either in the payload or pulled from the topic via the
    AWS IoT rule that forwards to the queue.

    The system must also be setup with a rule to forward [AWS Lifecycle
    events](https://docs.aws.amazon.com/iot/latest/developerguide/life-cycle-events.html)
    to a queue for tracking device online/offline presence

    Right now, all configured queues are handled by this module.
    In the future, we may want to separate handling for each
    queue in it's own module.
    """
    use Broadway

    alias Broadway.Message
    alias NervesHub.Devices

    require Logger

    def start_link(opts), do: Broadway.start_link(__MODULE__, opts)

    @impl Broadway
    def handle_message(_processor, %{data: raw} = msg, _context) do
      case Jason.decode(raw) do
        {:ok, data} ->
          Message.put_data(msg, data)
          |> process_message()

        _ ->
          Message.failed(msg, :malformed)
      end
    end

    @impl Broadway
    def handle_batch(_batcher, messages, batch_info, _context) do
      Logger.debug("[SQS] Handled #{inspect(batch_info.size)}")
      messages
    end

    defp process_message(%{data: %{"eventType" => "connected"} = data} = msg) do
      # TODO: Maybe use more info from the connection?
      # Example payload of AWS lifecycle connected event
      # principalIdentifier is a SHA256 fingerprint of the certificate that
      # is Base16 encoded
      # {
      #   "clientId": "186b5",
      #   "timestamp": 1573002230757,
      #   "eventType": "connected",
      #   "sessionIdentifier": "a4666d2a7d844ae4ac5d7b38c9cb7967",
      #   "principalIdentifier": "12345678901234567890123456789012",
      #   "ipAddress": "192.0.2.0",
      #   "versionNumber": 0
      # }

      with {:ok, device} <- Devices.get_by_identifier(data["clientId"]) do
        Logger.debug("[AWS IoT] device #{device.identifier} connected")

        Tracker.online(device)

        msg
      else
        _ ->
          Message.failed(msg, :unknown_device)
      end
    end

    defp process_message(%{data: %{"eventType" => "disconnected"} = data} = msg) do
      # TODO: Maybe use more of the disconnect data?
      # Example payload of AWS lifecyle disconnect event
      # {
      #   "clientId": "186b5",
      #   "timestamp": 1573002340451,
      #   "eventType": "disconnected",
      #   "sessionIdentifier": "a4666d2a7d844ae4ac5d7b38c9cb7967",
      #   "principalIdentifier": "12345678901234567890123456789012",
      #   "clientInitiatedDisconnect": true,
      #   "disconnectReason": "CLIENT_INITIATED_DISCONNECT",
      #   "versionNumber": 0
      # }
      with {:ok, device} <- Devices.get_by_identifier(data["clientId"]) do
        Logger.debug(
          "[AWS IoT] device #{device.identifier} disconnected: #{data["disconnectReason"]}"
        )

        Tracker.offline(device)
      end

      msg
    end

    defp process_message(msg) do
      # TODO: Track unhandled msg
      msg
    end
  end
end
