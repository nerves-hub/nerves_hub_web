defmodule NervesHub.RPC.DeviceAuth do
  @moduledoc false

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.Device
  alias NervesHub.Products
  alias NervesHub.Tracker

  alias Plug.Crypto

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  def connect_device({:ssl_certs, ssl_cert}) do
    X509.Certificate.from_der!(ssl_cert)
    |> Devices.get_device_by_x509()
    |> case do
      {:ok, device} ->
        {:ok, on_connect(device)}

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :cert,
          reason: error
        })

        {:error, :invalid_auth}
    end
  end

  def connect_device({:shared_secrets, x_headers}) do
    headers = Map.new(x_headers)

    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      {:ok, on_connect(device)}
    else
      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :shared_secrets,
          reason: error,
          product_key: Map.get(headers, "x-nh-key", "*empty*")
        })

        {:error, :invalid_auth}
    end
  end

  def disconnect_device({:error, {:shutdown, :disconnected}}, device, reference_id) do
    :telemetry.execute([:nerves_hub, :devices, :duplicate_connection], %{count: 1}, %{
      ref_id: reference_id,
      device: device
    })

    disconnect_device(:ok, device, reference_id)
  end

  def disconnect_device(_, device, reference_id) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1}, %{
      ref_id: reference_id,
      identifier: device.identifier
    })

    {:ok, _device_connection} = Connections.device_disconnected(reference_id)

    Tracker.offline(device)

    :ok
  end

  defp on_connect(%Device{status: :registered} = device) do
    Devices.set_as_provisioned!(device)
    |> on_connect()
  end

  defp on_connect(device) do
    # disconnect devices using the same identifier
    Phoenix.Channel.Server.broadcast_from!(
      NervesHub.PubSub,
      self(),
      "device_socket:#{device.id}",
      "disconnect",
      %{}
    )

    {:ok, %DeviceConnection{id: connection_id}} = Connections.device_connected(device.id)

    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: connection_id,
      identifier: device.identifier,
      firmware_uuid: get_in(device, [Access.key(:firmware_metadata), Access.key(:uuid)])
    })

    Tracker.online(device)

    {connection_id, Devices.preload_product(device)}
  end

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

  defp decode_from_headers(_headers), do: {:error, :headers_decode_failed}

  defp get_shared_secret_auth("nhp_" <> _ = key), do: Products.get_shared_secret_auth(key)
  defp get_shared_secret_auth(key), do: Devices.get_shared_secret_auth(key)

  defp get_or_maybe_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    # TODO: Support JITP profile here to decide if enabled or what tags to use
    Devices.get_or_create_device(auth, identifier)
  end

  defp get_or_maybe_create_device(%{device: %{identifier: identifier} = device}, identifier),
    do: {:ok, device}

  defp get_or_maybe_create_device(_auth, _identifier), do: {:error, :bad_identifier}

  defp max_hmac_age() do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(:max_age, @default_max_hmac_age)
  end

  defp check_shared_secret_enabled() do
    if Products.shared_secrets_enabled?() do
      :ok
    else
      {:error, :shared_secrets_not_enabled}
    end
  end
end
