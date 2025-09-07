defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket
  use OpenTelemetryDecorator

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Products
  alias NervesHub.Tracker

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device:*", NervesHubWeb.DeviceChannel)
  channel("extensions", NervesHubWeb.ExtensionsChannel)

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  defoverridable init: 1, handle_in: 2, terminate: 2

  @impl Phoenix.Socket.Transport
  def init(state_tuple) do
    {:ok, {state, socket}} = super(state_tuple)
    socket = on_connect(socket)
    {:ok, {state, socket}}
  end

  @impl Phoenix.Socket.Transport
  @decorate with_span("Channels.DeviceSocket.terminate")
  def terminate(reason, {channels_info, socket}) do
    socket = on_disconnect(reason, socket)
    super(reason, {channels_info, socket})
  end

  @impl Phoenix.Socket.Transport
  def handle_in(msg, {state, socket}) do
    socket = heartbeat(socket)
    super(msg, {state, socket})
  end

  @decorate with_span("Channels.DeviceSocket.heartbeat")
  defp heartbeat(%{assigns: %{device: device, reference_id: ref_id}} = socket) do
    if update_heartbeat?(socket) do
      Connections.device_heartbeat(device, ref_id)
    end

    last_message =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    assign(socket, :last_message_at, last_message)
  end

  defp heartbeat(socket), do: socket

  defp update_heartbeat?(%{assigns: %{last_message_at: last_message_at}}) do
    seconds_ago = DateTime.diff(DateTime.utc_now(), last_message_at, :second)

    seconds_ago >= last_seen_update_interval()
  end

  defp update_heartbeat?(_), do: false

  # Used by Devices connecting with SSL certificates
  @impl Phoenix.Socket
  @decorate with_span("Channels.DeviceSocket.connect")
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}}) when not is_nil(ssl_cert) do
    X509.Certificate.from_der!(ssl_cert)
    |> Devices.get_device_by_x509()
    |> case do
      {:ok, device} ->
        socket_and_assigns(socket, device)

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :cert,
          reason: error
        })

        {:error, :invalid_auth}
    end
  end

  # Used by Devices connecting with HMAC Shared Secrets
  @decorate with_span("Channels.DeviceSocket.connect")
  def connect(_params, socket, %{x_headers: x_headers})
      when is_list(x_headers) and (is_list(x_headers) and x_headers != []) do
    headers = Map.new(x_headers)

    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      socket_and_assigns(socket, device)
    else
      {:error,
       %Ecto.Changeset{
         changes: %{identifier: identifier, org_id: org_id, product_id: product_id},
         errors: [
           identifier: {_msg, [constraint: :unique, constraint_name: "devices_identifier_index"]}
         ]
       }} ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :shared_secrets,
          reason: :duplicate_device_identifier,
          org_id: org_id,
          product_id: product_id,
          identifier: identifier
        })

        {:error, :invalid_auth}

      {:error, :expired} ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :shared_secrets,
          reason: :signature_expired,
          shared_key: Map.get(headers, "x-nh-key", "*empty*")
        })

        {:error, :invalid_auth}

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :shared_secrets,
          reason: error,
          shared_key: Map.get(headers, "x-nh-key", "*empty*")
        })

        {:error, :invalid_auth}
    end
  rescue
    e in ArgumentError ->
      headers = Map.new(x_headers)

      :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
        auth: :shared_secrets,
        reason: e,
        shared_key: Map.get(headers, "x-nh-key", "*empty*")
      })

      {:error, :invalid_auth}
  end

  def connect(_params, _socket, _connect_info) do
    {:error, :no_auth}
  end

  @impl Phoenix.Socket
  def id(%{assigns: %{device: device}}), do: "device_socket:#{device.id}"
  def id(_socket), do: nil

  def drainer_configuration() do
    config = Application.get_env(:nerves_hub, :device_socket_drainer)

    [
      batch_size: config[:batch_size],
      batch_interval: config[:batch_interval],
      shutdown: config[:shutdown]
    ]
  end

  defp decode_from_headers(%{"x-nh-alg" => "NH1-HMAC-" <> alg} = headers) do
    with [digest_str, iter_str, key_len_str] <- String.split(alg, "-"),
         digest = String.to_existing_atom(String.downcase(digest_str)),
         {iterations, ""} <- Integer.parse(iter_str),
         {key_length, ""} <- Integer.parse(key_len_str),
         {signed_at, ""} <- Integer.parse(headers["x-nh-time"]),
         {:ok, key} <- Map.fetch(headers, "x-nh-key") do
      expected_salt = """
      NH1:device-socket:shared-secret:connect

      x-nh-alg=NH1-HMAC-#{alg}
      x-nh-key=#{key}
      x-nh-time=#{signed_at}
      """

      opts = [
        key_length: key_length,
        key_iterations: iterations,
        key_digest: digest,
        signed_at: signed_at,
        max_age: max_hmac_age()
      ]

      {:ok, key, expected_salt, opts}
    end
  end

  defp decode_from_headers(_headers), do: {:error, :headers_decode_failed}

  defp get_shared_secret_auth("nhp_" <> _ = key), do: Products.get_shared_secret_auth(key)
  defp get_shared_secret_auth(key), do: Devices.get_shared_secret_auth(key)

  defp get_or_maybe_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    # TODO: Support JITP profile here to decide if enabled or what tags to use
    Devices.get_or_create_device(auth, identifier)
  end

  defp get_or_maybe_create_device(%{device: %{identifier: identifier} = device}, identifier), do: {:ok, device}

  defp get_or_maybe_create_device(_auth, _identifier), do: {:error, :bad_identifier}

  defp max_hmac_age() do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(:max_age, @default_max_hmac_age)
  end

  defp check_shared_secret_enabled() do
    if shared_secrets_enabled?() do
      :ok
    else
      {:error, :shared_secrets_not_enabled}
    end
  end

  defp socket_and_assigns(socket, device) do
    # disconnect devices using the same identifier
    _ = socket.endpoint.broadcast_from(self(), "device_socket:#{device.id}", "disconnect", %{})

    socket =
      socket
      |> assign(:device, device)

    {:ok, socket}
  end

  @decorate with_span("Channels.DeviceSocket.on_connect#registered")
  defp on_connect(%{assigns: %{device: %{status: :registered} = device}} = socket) do
    socket
    |> assign(device: Devices.set_as_provisioned!(device))
    |> on_connect()
  end

  @decorate with_span("Channels.DeviceSocket.on_connect#provisioned")
  defp on_connect(%{assigns: %{device: device}} = socket) do
    # Report connection and use connection id as reference
    {:ok, %DeviceConnection{id: connection_id}} =
      Connections.device_connecting(device.id, device.product_id)

    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: connection_id,
      identifier: socket.assigns.device.identifier,
      firmware_uuid: get_in(socket.assigns.device, [Access.key(:firmware_metadata), Access.key(:uuid)])
    })

    Tracker.online(device)

    # this is required by `DeviceJSONSerializer` which needs to update the message topic,
    # allowing for the socket to map messages correctly
    #
    # we could remove this and instead modify the payload in `handle_in`, but I favoured
    # this approach as it simplifies the logic in `handle_in` and keeps the topic remapping
    # logic in one place, the serializer
    Process.put(:device_id, device.id)

    socket
    |> assign(:device, device)
    |> assign(:reference_id, connection_id)
  end

  defp on_disconnect(_reason, %{assigns: %{disconnection_handled?: true} = socket}) do
    socket
  end

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect(reason, socket) do
    %{assigns: %{device: device, reference_id: reference_id}} = socket

    if reason == {:error, {:shutdown, :disconnected}} do
      :telemetry.execute([:nerves_hub, :devices, :duplicate_connection], %{count: 1}, %{
        ref_id: reference_id,
        device: device
      })
    end

    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1}, %{
      ref_id: reference_id,
      identifier: device.identifier
    })

    :ok = Connections.device_disconnected(reference_id)

    Tracker.offline(device)

    assign(socket, :disconnection_handled?, true)
  end

  defp last_seen_update_interval() do
    interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes) * 60

    jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)

    interval + Enum.random(-jitter..jitter)
  end

  def shared_secrets_enabled?() do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(:shared_secrets, [])
    |> Keyword.get(:enabled, false)
  end
end
