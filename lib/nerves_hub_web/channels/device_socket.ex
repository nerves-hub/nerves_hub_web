defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products
  alias NervesHub.Tracker

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  defoverridable init: 1, handle_info: 2, terminate: 2

  @impl true
  def init(state) do
    res = {:ok, {_, socket}} = super(state)
    on_connect(socket.assigns)
    res
  end

  @impl true
  def terminate(reason, {_channels_info, socket} = state) do
    on_disconnect(socket.assigns)
    super(reason, state)
  end

  @impl true
  def handle_info(:update_connection_last_seen, %{assigns: %{device: device}} = socket) do
    {:ok, _device} = Devices.device_heartbeat(device)

    _ =
      NervesHubWeb.DeviceEndpoint.broadcast(
        "device:#{device.identifier}:internal",
        "connection:heartbeat",
        %{}
      )

    Process.send_after(self(), :update_connection_last_seen, last_seen_update_interval())

    {:ok, socket}
  end

  def handle_info(msg, socket) do
    super(msg, socket)
  end

  # Used by Devices connecting with SSL certificates
  @impl true
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}})
      when not is_nil(ssl_cert) do
    X509.Certificate.from_der!(ssl_cert)
    |> Devices.get_device_certificate_by_x509()
    |> case do
      {:ok, %{device: %Device{} = device}} ->
        socket_and_assigns(socket, device)

      _e ->
        {:error, :invalid_auth}
    end
  end

  # Used by Devices connecting with HMAC Shared Secrets
  def connect(_params, socket, %{x_headers: x_headers})
      when is_list(x_headers) and length(x_headers) > 0 do
    headers = Map.new(x_headers)

    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      socket_and_assigns(socket, device)
    else
      error ->
        Logger.info("device authentication failed : #{inspect(error)}")
        {:error, :invalid_auth}
    end
  end

  def connect(_params, _socket, _connect_info) do
    {:error, :no_auth}
  end

  @impl true
  def id(%{assigns: %{device: device}}), do: "device_socket:#{device.id}"
  def id(_socket), do: nil

  defp decode_from_headers(%{"x-nh-alg" => "NH1-HMAC-" <> alg} = headers) do
    with [digest_str, iter_str, klen_str] <- String.split(alg, "-"),
         digest <- String.to_existing_atom(String.downcase(digest_str)),
         {iterations, ""} <- Integer.parse(iter_str),
         {key_length, ""} <- Integer.parse(klen_str),
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

  defp decode_from_headers(_headers), do: :error

  defp get_shared_secret_auth("nhp_" <> _ = key), do: Products.get_shared_secret_auth(key)
  defp get_shared_secret_auth(key), do: Devices.get_shared_secret_auth(key)

  defp get_or_maybe_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    # TODO: Support JITP profile here to decide if enabled or what tags to use
    Devices.get_or_create_device(auth, identifier)
  end

  defp get_or_maybe_create_device(%{device: %{identifier: identifier} = device}, identifier),
    do: {:ok, device}

  defp get_or_maybe_create_device(_auth, _identifier), do: {:error, :bad_identifier}

  defp generate_reference_id() do
    Base.encode32(:crypto.strong_rand_bytes(2), padding: false)
  end

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

  def shared_secrets_enabled?() do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(:shared_secrets, [])
    |> Keyword.get(:enabled, false)
  end

  defp socket_and_assigns(socket, device) do
    # disconnect devices using the same identifier
    _ = NervesHubWeb.DeviceEndpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    socket =
      socket
      |> assign(:device, device)
      |> assign(:reference_id, generate_reference_id())

    {:ok, socket}
  end

  def on_connect(%{device: device, reference_id: reference_id} = _assigns) do
    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: reference_id,
      identifier: device.identifier,
      firmware_uuid: get_in(device, [Access.key(:firmware_metadata), Access.key(:uuid)])
    })

    {:ok, _} = Devices.device_connected(device)

    Process.send_after(self(), :update_connection_last_seen, last_seen_update_interval())

    Tracker.online(device)
  end

  def on_disconnect(%{device: device, reference_id: reference_id} = _assigns) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{}, %{
      ref_id: reference_id,
      identifier: device.identifier
    })

    {:ok, device} = Devices.device_disconnected(device)

    Tracker.offline(device)

    :ok
  end

  defp last_seen_update_interval() do
    Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
    |> :timer.minutes()
  end
end
