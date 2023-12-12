defmodule NervesHubWeb.DeviceSocketSharedSecretAuth do
  use Phoenix.Socket

  alias NervesHub.Devices
  alias NervesHub.Products

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)

  # Default 1 min max age for the signature
  @default_max_age 60

  def connect(_params, socket, %{x_headers: headers}) do
    with {:ok, config} <- Application.get_env(:nerves_hub, __MODULE__, []),
         {:ok, true} <- Keyword.fetch(config, :enabled),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- Products.get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- Devices.get_or_create_device(auth, identifier) do
      socket =
        socket
        |> assign(:device, device)
        |> assign(:reference_id, generate_reference_id())

      {:ok, socket}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

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
        max_age: @default_max_age
      ]

      {:ok, key, expected_salt, opts}
    end
  end

  defp decode_from_headers(_headers), do: :error

  defp generate_reference_id() do
    Base.encode32(:crypto.strong_rand_bytes(2), padding: false)
  end
end
