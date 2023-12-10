defmodule NervesHubWeb.DeviceSocketTokenAuth do
  use Phoenix.Socket

  alias NervesHub.Devices

  alias Plug.Crypto

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)

  @salt_headers [
    "x-nh-key-digest",
    "x-nh-key-iterations",
    "x-nh-key-length",
    "x-nh-access-id",
    "x-nh-time"
  ]

  # Default 15 min max age for the signature
  @default_max_age 900

  def connect(_params, socket, %{x_headers: headers}) do
    parsed_data = parse_headers(headers)
    verify_opts = verification_options(parsed_data)
    salt = expected_salt(headers)

    with {:ok, true} <- Application.fetch_env(:nerves_hub, __MODULE__)[:enabled],
         {:ok, access_id} <- Keyword.fetch(parsed_data, :access_id),
         {:ok, token_auth} <- get_product_token_auth(access_id),
         {:ok, signature} <- Keyword.fetch(parsed_data, :signature),
         {:ok, identifier} <- Crypto.verify(token_auth.secret, salt, signature, verify_opts),
         {:ok, device} <-
           Devices.get_or_create_device(token_auth: token_auth, identifier: identifier) do
      socket =
        socket
        |> assign(:device, device)
        |> assign(:reference_id, generate_reference_id())

      {:ok, socket}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  def id(%{assigns: %{device: device}}), do: "device_socket:#{device.id}"
  def id(_socket), do: nil

  defp parse_headers(headers) do
    for {k, v} <- headers do
      case String.downcase(k) do
        "x-nh-time" ->
          {:signed_at, String.to_integer(v)}

        "x-nh-key-length" ->
          {:key_length, String.to_integer(v)}

        "x-nh-key-iterations" ->
          {:key_iterations, String.to_integer(v)}

        "x-nh-key-digest" ->
          "NH1-HMAC-" <> digest_str = v
          {:key_digest, String.to_existing_atom(String.downcase(digest_str))}

        "x-nh-access-id" ->
          {:access_id, v}

        "x-nh-signature" ->
          {:signature, v}

        _ ->
          # Skip unknown x headers.
          # It's not uncommon for x headers to be added by Load balancers
          nil
      end
    end
  end

  defp verification_options(parsed_data) do
    Keyword.take(parsed_data, [:key_digest, :key_iterations, :key_length, :signed_at])
    # TODO: Make max_age configurable?
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

  defp get_product_token_auth(access_id) do
    case NervesHub.Products.get_token_auth(access_id: access_id) do
      nil -> {:error, :unknown_access_id}
      token_auth -> {:ok, token_auth}
    end
  end

  defp generate_reference_id() do
    Base.encode32(:crypto.strong_rand_bytes(2), padding: false)
  end
end
