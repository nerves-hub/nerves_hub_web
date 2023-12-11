defmodule NervesHubWeb.DeviceSocketSharedSecretAuth do
  use Phoenix.Socket

  alias NervesHub.Devices
  alias NervesHub.Products

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)

  @salt_headers [
    "x-nh-digest",
    "x-nh-iterations",
    "x-nh-length",
    "x-nh-key",
    "x-nh-time"
  ]

  # Default 1 min max age for the signature
  @default_max_age 60

  def connect(_params, socket, %{x_headers: headers}) do
    parsed_headers = parse_headers(headers)
    verification_options = verification_options(parsed_headers)
    salt = expected_salt(headers)

    with {:ok, true} <- Application.fetch_env(:nerves_hub, __MODULE__)[:enabled],
         {:ok, key} <- Keyword.fetch(parsed_headers, :key),
         {:ok, auth} <- Products.get_shared_secret_auth(key),
         {:ok, signature} <- Keyword.fetch(parsed_headers, :signature),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_options),
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

  defp parse_headers(headers) do
    for {k, v} <- headers do
      case String.downcase(k) do
        "x-nh-digest" ->
          "NH1-HMAC-" <> digest_str = v
          {:key_digest, String.to_existing_atom(String.downcase(digest_str))}

        "x-nh-iterations" ->
          {:key_iterations, String.to_integer(v)}

        "x-nh-length" ->
          {:key_length, String.to_integer(v)}

        "x-nh-key" ->
          {:key, v}

        "x-nh-signature" ->
          {:signature, v}

        "x-nh-time" ->
          {:signed_at, String.to_integer(v)}

        _ ->
          # Skip unknown x headers.
          # It's not uncommon for x headers to be added by Load balancers
          nil
      end
    end
  end

  defp verification_options(parsed_data) do
    Keyword.take(parsed_data, [:key_digest, :key_iterations, :key_length, :signed_at])
    |> Keyword.put(:max_age, @default_max_age)
  end

  defp expected_salt(headers) do
    salt_headers =
      Enum.filter(headers, &(elem(&1, 0) in @salt_headers))
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)

    """
    NH1:device:token:connect

    #{salt_headers}
    """
  end

  defp generate_reference_id() do
    Base.encode32(:crypto.strong_rand_bytes(2), padding: false)
  end
end
