defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  # Used by Devices connecting with SSL certificates
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}} = connect_info)
      when not is_nil(ssl_cert) do
    X509.Certificate.from_der!(ssl_cert)
    |> Devices.get_device_certificate_by_x509()
    |> case do
      {:ok, %{device: %Device{} = device}} ->
        socket_and_assigns(socket, device, connect_info)

      _e ->
        {:error, :invalid_auth}
    end
  end

  # Used by Devices connecting with HMAC Shared Secrets
  def connect(_params, socket, %{x_headers: x_headers} = connect_info)
      when is_list(x_headers) and length(x_headers) > 0 do
    headers = Map.new(x_headers)

    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      socket_and_assigns(socket, device, connect_info)
    else
      error ->
        Logger.info("device authentication failed : #{inspect(error)}")
        {:error, :invalid_auth}
    end
  end

  def connect(_params, _socket, _connect_info) do
    {:error, :no_auth}
  end

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

  defp ip_information(connect_info) do
    cond do
      forwarded_for = x_forwarded_for(connect_info) ->
        forwarded_for

      address = connect_info[:peer_data][:address] ->
        to_string(:inet.ntoa(address))

      true ->
        nil
    end
  end

  defp x_forwarded_for(connect_info) do
    (connect_info[:x_headers] || [])
    |> Enum.find_value(fn
      {"x-forwarded-for", val} ->
        hd(String.split(val, ","))

      _ ->
        nil
    end)
  end

  defp socket_and_assigns(socket, device, connect_info) do
    socket =
      socket
      |> assign(:device, device)
      |> assign(:reference_id, generate_reference_id())
      |> assign(:request_ip, ip_information(connect_info))

    {:ok, socket}
  end
end
