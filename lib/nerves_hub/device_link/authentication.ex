defmodule NervesHub.DeviceLink.Authentication do
  @moduledoc """
  Authenticates a connecting device and resolves it to a `DeviceInfo`.

  Reached through `NervesHub.DeviceLink`. Devices present either a client
  certificate or an HMAC shared secret; both paths end with the device being
  marked provisioned if this is its first connection, and its allowed extensions
  resolved from the product and device settings.

  The HMAC check cannot be split from this module: verifying the signature needs
  the shared secret itself, which only the platform holds. So a caller that has
  no database — a proxy holding the socket, say — has to hand the headers over
  whole rather than pre-checking anything.
  """

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Certificates
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias Plug.Crypto

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  # This config key predates the move out of NervesHubWeb.DeviceSocket. It is a
  # deployment contract (DEVICE_SHARED_SECRETS_ENABLED maps onto it in
  # runtime.exs), so it stays put rather than being renamed to match this module.
  @config_key NervesHubWeb.DeviceSocket

  @type credentials() :: {:ssl_cert, binary()} | {:shared_secret, headers :: map()}

  @doc """
  Identify the device behind a set of credentials.

  Failures are deliberately flattened to `:invalid_auth` — the detail is
  recorded as telemetry here, where it is known, rather than being handed back
  to the caller.
  """
  @spec authenticate(credentials()) :: {:ok, DeviceInfo.t()} | {:error, :invalid_auth}
  def authenticate({:ssl_cert, ssl_cert}) do
    X509.Certificate.from_der!(ssl_cert)
    |> Certificates.get_device_by_x509()
    |> case do
      {:ok, device} ->
        {:ok, device_info(device)}

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :cert,
          reason: error
        })

        {:error, :invalid_auth}
    end
  end

  def authenticate({:shared_secret, headers}) do
    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      {:ok, device_info(device)}
    else
      {:error,
       %Ecto.Changeset{
         changes: %{identifier: identifier, org_id: org_id, product_id: product_id},
         errors: [
           identifier: {_msg, [constraint: :unique, constraint_name: "devices_identifier_index"]}
         ]
       }} ->
        _ =
          ProductNotifications.create_duplicate_device_identifier_notification!(
            product_id,
            identifier,
            :shared_secret
          )

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
      :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
        auth: :shared_secrets,
        reason: e,
        shared_key: Map.get(headers, "x-nh-key", "*empty*")
      })

      {:error, :invalid_auth}
  end

  @doc "Whether devices may authenticate with an HMAC shared secret."
  @spec shared_secrets_enabled?() :: boolean()
  def shared_secrets_enabled?() do
    Application.get_env(:nerves_hub, @config_key, [])
    |> Keyword.get(:shared_secrets, [])
    |> Keyword.get(:enabled, false)
  end

  # ---------------------------------------------------------------- internals

  defp device_info(device) do
    if device.status == :registered do
      Devices.set_as_provisioned!(device)
    end

    %DeviceInfo{
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      device_identifier: device.identifier,
      deployment_id: device.deployment_id,
      firmware_metadata: device.firmware_metadata,
      device_updates_enabled: device.updates_enabled,
      device_updates_blocked_until: device.updates_blocked_until,
      allowed_extensions: calculate_allowed_extensions(device)
    }
  end

  defp calculate_allowed_extensions(device) do
    for {extension, true} <- Map.from_struct(device.product.extensions),
        {^extension, device_enabled?} <- Map.from_struct(device.extensions),
        device_enabled? != false,
        do: extension
  end

  defp check_shared_secret_enabled() do
    if shared_secrets_enabled?() do
      :ok
    else
      {:error, :shared_secrets_not_enabled}
    end
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
    Application.get_env(:nerves_hub, @config_key, [])
    |> Keyword.get(:max_age, @default_max_hmac_age)
  end
end
