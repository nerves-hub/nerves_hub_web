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

  alias NervesHub.Accounts
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias Plug.Crypto

  # Default 90 seconds max age for the signature
  @default_max_hmac_age 90

  # The most PBKDF2 work a connecting device may ask for. See
  # `check_key_derivation/2`.
  @max_key_iterations 10_000
  @max_key_length 64

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

  A device that has been deleted is refused, and so is one whose product has
  been, on its own or along with its org. So is a device in another org's
  product, which would be offered that org's firmware.

  `server_name` is the hostname the device asked for in its TLS handshake, if it
  asked for one. A device is refused on a hostname that only other orgs have claimed.
  That comes before the device is marked provisioned, as it hasn't connected.
  """
  @spec authenticate(credentials(), server_name :: String.t() | nil) ::
          {:ok, DeviceInfo.t()} | {:error, :invalid_auth}
  def authenticate(credentials, server_name \\ nil) do
    with {:ok, device} <- identify(credentials),
         :ok <- check_not_deleted(device),
         :ok <- check_product_in_org(device),
         :ok <- check_hostname(device, server_name) do
      {:ok, device_info(device)}
    end
  end

  defp identify({:ssl_cert, ssl_cert}) do
    X509.Certificate.from_der!(ssl_cert)
    |> Certificates.get_device_by_x509()
    |> case do
      {:ok, device} ->
        {:ok, device}

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :cert,
          reason: error
        })

        {:error, :invalid_auth}
    end
  end

  defp identify({:shared_secret, headers}) do
    with :ok <- check_shared_secret_enabled(),
         {:ok, key, salt, verification_opts} <- decode_from_headers(headers),
         {:ok, auth} <- get_shared_secret_auth(key),
         {:ok, signature} <- Map.fetch(headers, "x-nh-signature"),
         {:ok, identifier} <- Crypto.verify(auth.secret, salt, signature, verification_opts),
         {:ok, device} <- get_or_maybe_create_device(auth, identifier) do
      _ = mark_last_used(auth)
      {:ok, device}
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

  # Deleting an org deletes its products, so the product covers both. A product
  # key stops working with its product, but a certificate or a device's own key
  # belongs to the device, which deleting its product or org leaves in place.
  defp check_not_deleted(%Device{deleted_at: nil, product: %{deleted_at: nil}}), do: :ok

  defp check_not_deleted(device) do
    :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
      reason: :deleted,
      org_id: device.org_id,
      product_id: device.product_id,
      identifier: device.identifier
    })

    {:error, :invalid_auth}
  end

  # Nothing makes a device whose org doesn't own its product: creating or moving
  # one sets both from the product. Request params could once set either on its
  # own, though, and deployment groups are matched by product alone, so such a
  # device would be offered the other org's firmware.
  defp check_product_in_org(%Device{org_id: org_id, product: %{org_id: org_id}}), do: :ok

  defp check_product_in_org(device) do
    :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
      reason: :product_in_other_org,
      org_id: device.org_id,
      product_id: device.product_id,
      identifier: device.identifier
    })

    {:error, :invalid_auth}
  end

  defp check_hostname(_device, nil), do: :ok

  defp check_hostname(device, server_name) do
    if Accounts.device_hostname_allowed?(device.org_id, server_name) do
      :ok
    else
      :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
        reason: :wrong_hostname,
        server_name: server_name,
        org_id: device.org_id,
        product_id: device.product_id,
        identifier: device.identifier
      })

      {:error, :invalid_auth}
    end
  end

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
      device_update_mode: device.update_mode,
      managed_updates_allowed: device.managed_updates_allowed,
      device_updates_enabled: Device.updates_enabled?(device),
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
         :ok <- check_key_derivation(iterations, key_length),
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
        max_age: max_hmac_age(),
        # Plug.Crypto caches each derived key in the `Plug.Crypto.Keys` ETS
        # table unless told not to, keyed on the salt, and never evicts. This
        # salt carries the signing time, so no two connections share one: the
        # cache never hits, and every connect leaves a row behind for the life
        # of the node. A production device node held 150,917 of them (41.5MB of
        # ETS, plus the salts in binary memory) after 12 days.
        cache: nil
      ]

      {:ok, key, expected_salt, opts}
    end
  end

  defp decode_from_headers(_headers), do: {:error, :headers_decode_failed}

  # The device names its own key derivation in `x-nh-alg`, and the key is
  # derived before the signature can be checked, so a request naming a real key
  # gets whatever work it asks for, secret or no secret. Unbounded, one request
  # could hold a dirty CPU scheduler for minutes, or ask for a key gigabytes
  # long.
  #
  # NervesHubLink, nerves-hub-link-agent and nerves-hub-link-esp32 all send
  # 1,000 iterations and a 32 byte key. NervesHubLink lets an app change both,
  # so the limits leave room above that while keeping a derivation to around a
  # millisecond. A device asking for more is logged as
  # `:key_derivation_out_of_range` and refused. Raising a limit here lets it
  # back in, with no change on the device.
  defp check_key_derivation(iterations, key_length)
       when iterations in 1..@max_key_iterations//1 and key_length in 1..@max_key_length//1, do: :ok

  defp check_key_derivation(_iterations, _key_length), do: {:error, :key_derivation_out_of_range}

  defp get_shared_secret_auth("nhp_" <> _ = key), do: Products.get_shared_secret_auth(key)
  defp get_shared_secret_auth(key), do: Devices.get_shared_secret_auth(key)

  defp mark_last_used(%Devices.SharedSecretAuth{} = auth), do: Devices.mark_last_used(auth)
  defp mark_last_used(_product_auth), do: :ok

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
