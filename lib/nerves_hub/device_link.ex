defmodule NervesHub.DeviceLink do
  @moduledoc """
  Encapsulation of device connection workflow logic
  """

  alias NervesHub.Accounts
  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceLink.Authentication
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Effect
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions.Dispatch, as: ExtensionDispatch
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments
  alias Phoenix.Channel.Server, as: ChannelServer
  alias Phoenix.Socket.Broadcast

  require Logger

  @public_key_types ["fwup_public_keys", "archive_public_keys"]

  # ------------------------------------------------------------------------
  # Device channel
  #
  # Four entry points covering everything that can happen on a device's link:
  # it joins, it says something, something in the platform addresses it, or a
  # broadcast needs handling before the device sees it. Each takes the session
  # and returns a new one plus effects — see `NervesHub.DeviceLink.Effect`.
  # ------------------------------------------------------------------------

  @doc """
  The device has joined its channel.
  """
  @spec device_join(DeviceInfo.t(), params :: map()) ::
          {:ok, Session.t(), [Effect.t()]} | {:error, any()}
  def device_join(device_info, params) do
    params = sanitize_device_api_version(params)

    case join(device_info, params) do
      {:ok, device_info} ->
        session = %Session{
          device_info: device_info,
          device_api_version: params["device_api_version"],
          currently_downloading_uuid: params["currently_downloading_uuid"]
        }

        {session, effects} = follow_deployment_group(session)

        {:ok, session, effects ++ [{:send_self, {:after_join, params}}]}

      error ->
        :telemetry.execute([:nerves_hub, :devices, :join_failure], %{count: 1}, %{
          identifier: device_info.device_identifier,
          channel: "device",
          error: error
        })

        {:error, error}
    end
  end

  @doc """
  The device sent us something.
  """
  @spec device_message(Session.t(), event :: String.t(), payload :: map()) :: {Session.t(), [Effect.t()]}
  def device_message(session, "firmware_validated", _payload) do
    :ok = firmware_validated(session.device_info)
    {session, []}
  end

  # `fwup_progress` is what every deployed nerves_hub_link sends, and devices in
  # the field cannot be made to send anything else, so it can never be retired.
  # `update_progress` is the same message under a name that does not presume
  # fwup, and is what a non-Nerves agent should send. Both carry the same
  # payload: a `value` percentage and an optional `stage`.
  def device_message(session, event, %{"value" => percent} = params)
      when event in ["fwup_progress", "update_progress"] do
    {stage, percent} =
      case {params["stage"], percent} do
        {nil, 100} -> {"completed", nil}
        {nil, _} -> {"updating", percent}
        {stage, _} -> {stage, percent}
      end

    :ok = status_update(session.device_info, %{"status" => stage, "progress" => percent})

    {session, []}
  end

  def device_message(session, "connection_types", %{"values" => types}) do
    :ok = update_connection_metadata(session.device_info.connection_ref, %{"connection_types" => types})

    {session, []}
  end

  def device_message(session, "status_update", params) do
    :ok = status_update(session.device_info, params)
    {session, []}
  end

  def device_message(session, "rebooting", _payload), do: {session, []}

  def device_message(session, "scripts/run", %{
        "ref" => "connecting_code",
        "result" => result,
        "return" => return,
        "output" => output
      })
      when result == "error" or return == "nil" do
    :telemetry.execute([:nerves_hub, :devices, :connecting_code_failure], %{
      output: output,
      identifier: session.device_info.device_identifier
    })

    {session, []}
  end

  def device_message(session, "scripts/run", %{"ref" => "connecting_code"}) do
    :telemetry.execute([:nerves_hub, :devices, :connecting_code_success], %{count: 1})
    {session, []}
  end

  def device_message(session, "scripts/run", params) do
    ref = params["ref"]

    case session.script_refs[ref] do
      nil ->
        # Either the script already timed out, or the device answered twice.
        {session, []}

      pid ->
        output =
          [params["output"], params["return"]]
          |> Enum.join("\n")
          |> String.trim()

        send(pid, {:output, output})

        # The script answered, so release the reference and the timeout that was
        # only there in case it never did.
        {release_script_ref(session, ref), [cancel_script_timeout(ref)]}
    end
  end

  def device_message(session, "report_network_interface", %{"interface" => interface}) do
    case report_network_interface(session.device_info, interface) do
      {:ok, device_info} ->
        {%{session | device_info: device_info}, []}

      :unchanged ->
        {session, []}

      :error ->
        Logger.warning("[DeviceChannel] could not update device network interface.")
        {session, []}
    end
  end

  def device_message(session, event, params) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    :telemetry.execute([:nerves_hub, :devices, :unhandled_in], %{count: 1}, %{
      identifier: session.device_info.device_identifier,
      msg: event,
      params: params
    })

    {session, []}
  end

  @doc """
  Something in the platform addressed this device's link directly.
  """
  @spec device_notify(Session.t(), message :: term()) :: {Session.t(), [Effect.t()]}
  def device_notify(session, {:after_join, params}) do
    :ok = after_join(session.device_info, params)

    effects =
      session.device_info
      |> fetch_connecting_code()
      |> connecting_code_effects(session)

    {session, effects}
  end

  # we can ignore this message
  def device_notify(session, %Broadcast{event: "deployments/update"}), do: {session, []}

  # listen for notifications about archive updates for deployment groups
  def device_notify(session, %Broadcast{event: "archives/updated"}) do
    :ok = maybe_send_archive(session.device_info, session.device_api_version, audit_log: true)
    {session, []}
  end

  def device_notify(session, {:run_script, pid, text}) do
    if safe_to_run_scripts?(session) do
      ref = Base.encode64(:crypto.strong_rand_bytes(4), padding: false)
      session = %{session | script_refs: Map.put(session.script_refs, ref, pid)}

      {session,
       [
         {:push, "scripts/run", %{"text" => text, "ref" => ref}},
         {:send_after, {:script_ref, ref}, {:clear_script_ref, ref}, 15_000}
       ]}
    else
      send(pid, {:error, :incompatible_version})
      {session, []}
    end
  end

  # The script never answered. Drop the reference, and the timeout's own
  # bookkeeping with it -- a one-shot timer that has fired leaves an entry
  # behind otherwise, and on a connection held for weeks those accumulate.
  def device_notify(session, {:clear_script_ref, ref}) do
    {release_script_ref(session, ref), [cancel_script_timeout(ref)]}
  end

  def device_notify(session, message) do
    :telemetry.execute([:nerves_hub, :devices, :unhandled_info], %{count: 1}, %{
      identifier: session.device_info.device_identifier,
      msg: message
    })

    {session, []}
  end

  @doc """
  An intercepted broadcast, handled before the device sees anything.
  """
  @spec device_broadcast(Session.t(), event :: String.t(), payload :: map()) :: {Session.t(), [Effect.t()]}
  def device_broadcast(session, "updated", _payload) do
    device_info = refresh_device_info(session.device_info)
    :ok = maybe_send_archive(device_info, session.device_api_version, audit_log: true)

    follow_deployment_group(%{session | device_info: device_info})
  end

  def device_broadcast(session, "deployment_updated", payload) do
    device_info = %{session.device_info | deployment_id: payload.deployment_id}
    :ok = maybe_send_archive(device_info, session.device_api_version, audit_log: true)

    follow_deployment_group(%{session | device_info: device_info})
  end

  defp release_script_ref(session, ref) do
    %{session | script_refs: Map.delete(session.script_refs, ref)}
  end

  defp cancel_script_timeout(ref), do: {:cancel_timer, {:script_ref, ref}}

  # A device only follows its own deployment group's topic, and that can change
  # underneath it, so every path that touches deployment_id comes back here.
  defp follow_deployment_group(session) do
    topic = deployment_topic(session.device_info)

    if topic == session.deployment_topic do
      {session, []}
    else
      leave = if session.deployment_topic, do: [{:unsubscribe, session.deployment_topic}], else: []
      join = if topic, do: [{:subscribe, topic}], else: []

      {%{session | deployment_topic: topic}, leave ++ join}
    end
  end

  defp deployment_topic(%{deployment_id: nil}), do: nil
  defp deployment_topic(%{deployment_id: id}), do: "deployment:#{id}"

  defp connecting_code_effects(nil, _session), do: []

  defp connecting_code_effects(connecting_code, session) when is_list(connecting_code) do
    connecting_code = Enum.join(connecting_code, "\n")

    if safe_to_run_scripts?(session) do
      # connecting code first in the case it attempts to change things before the other messages
      [{:push, "scripts/run", %{"text" => connecting_code, "ref" => "connecting_code"}}]
    else
      text = ~s/#{connecting_code}\n\r/
      topic = "device:console:#{session.device_info.device_id}"

      :ok = ChannelServer.broadcast_from!(NervesHub.PubSub, self(), topic, "dn", %{"data" => text})

      []
    end
  end

  defp safe_to_run_scripts?(session), do: Version.match?(session.device_api_version, ">= 2.1.0")

  defp sanitize_device_api_version(%{"device_api_version" => version} = params) do
    case Version.parse(version) do
      {:ok, _} ->
        params

      :error ->
        Logger.warning("[DeviceChannel] invalid device_api_version value - #{inspect(version)}")

        Map.put(params, "device_api_version", "1.0.0")
    end
  end

  defp sanitize_device_api_version(params) do
    Logger.warning("[DeviceChannel] device_api_version is missing from the connection params")
    Map.put(params, "device_api_version", "1.0.0")
  end

  @doc """
  Identify the device behind a set of credentials.

  See `NervesHub.DeviceLink.Authentication`. Failures are flattened to
  `:invalid_auth`; the detail is recorded as telemetry where it is known.
  """
  @spec authenticate(Authentication.credentials()) :: {:ok, DeviceInfo.t()} | {:error, :invalid_auth}
  defdelegate authenticate(credentials), to: Authentication

  @doc "Whether devices may authenticate with an HMAC shared secret."
  @spec shared_secrets_enabled?() :: boolean()
  defdelegate shared_secrets_enabled?(), to: Authentication

  @doc """
  Whether to accept a certificate at this point in path validation.

  See `NervesHub.SSL.decide/2`. Reached from inside a TLS handshake, possibly on
  a node with no database, so it takes DER rather than a decoded certificate.
  """
  @spec verify_peer(der :: binary(), event :: NervesHub.SSL.event()) ::
          :valid | {:fail, NervesHub.SSL.reason()}
  def verify_peer(der, event), do: NervesHub.SSL.decide(der, event)

  @doc """
  Record that an authenticated device has connected.

  Returns the device info stamped with the connection reference that the rest of
  the connection's lifecycle is keyed by.
  """
  @spec connect(DeviceInfo.t()) :: {:ok, DeviceInfo.t()} | {:error, Ecto.Changeset.t()}
  def connect(device_info) do
    case Connections.device_connecting(device_info.org_id, device_info.product_id, device_info.device_id) do
      {:ok, %DeviceConnection{id: connection_id}} ->
        {:ok, %{device_info | connection_ref: connection_id}}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  The device is still there.
  """
  @spec heartbeat(connection_ref :: String.t()) :: :ok | :error
  def heartbeat(connection_ref) do
    Connections.device_heartbeat(connection_ref)
  end

  @doc """
  The device has gone.

  Returns an error when the reference is stale — the device may already have
  reconnected elsewhere, replacing the connection row — which callers can ignore.
  """
  @spec disconnect(connection_ref :: String.t(), reason :: String.t() | nil) :: :ok | {:error, any()}
  def disconnect(connection_ref, reason \\ nil) do
    Connections.device_disconnected(connection_ref, reason)
  end

  @spec join(DeviceInfo.t(), params :: map()) :: {:ok, DeviceInfo.t()} | {:error, any()}
  def join(device_info, params) do
    updated_metadata = %{
      "device_api_version" => params["device_api_version"]
    }

    device = Devices.get_device(device_info.device_id)

    with {:ok, device} <- update_firmware_metadata(device, params),
         :ok <- update_connection_metadata(device_info.connection_ref, updated_metadata),
         :ok <- maybe_clear_inflight_update(device, params) do
      device = refresh_deployment_group(device)

      {:ok, %{device_info | deployment_id: device.deployment_id, firmware_metadata: device.firmware_metadata}}
    else
      err -> {:error, err}
    end
  end

  @spec after_join(DeviceInfo.t(), params :: map()) :: :ok | {:error, any()}
  def after_join(device_info, params) do
    with :ok <- maybe_send_public_keys(device_info, params),
         :ok <- maybe_send_archive(device_info, params["device_api_version"]),
         :ok <- maybe_request_extensions(device_info, params["device_api_version"]) do
      announce_online(device_info)
    end
  rescue
    err -> {:error, err}
  end

  @spec refresh_device_info(DeviceInfo.t()) :: DeviceInfo.t()
  def refresh_device_info(device_info) do
    device = Devices.get_device(device_info.device_id)
    device_connection = Devices.Connections.get_latest_for_device(device_info.device_id)

    %{
      device_info
      | org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        device_identifier: device.identifier,
        deployment_id: device.deployment_id,
        firmware_metadata: device.firmware_metadata,
        device_updates_enabled: device.updates_enabled,
        device_updates_blocked_until: device.updates_blocked_until,
        device_network_interface: device_connection.network_interface
    }
  end

  @spec fetch_connecting_code(DeviceInfo.t()) :: list(binary()) | nil
  def fetch_connecting_code(device_info) do
    {device_connecting_code, deployment_connecting_code} = Devices.fetch_connecting_code(device_info.device_id)

    [deployment_connecting_code, device_connecting_code]
    |> Enum.filter(&(not is_nil(&1) and byte_size(&1) > 0))
    |> case do
      list when list == [] -> nil
      list -> list
    end
  end

  @spec update_connection_metadata(reference_id :: String.t(), metadata :: map()) :: :ok | {:error, any()}
  def update_connection_metadata(reference_id, metadata) do
    Connections.merge_update_metadata(reference_id, metadata)
  end

  @typedoc """
  An effect for the caller to carry out on the device connection.

  See `NervesHub.Extensions.Dispatch` — routing is already resolved, so the
  caller sends opaque terms and keys timers by opaque handles.
  """
  @type extension_effect() :: ExtensionDispatch.effect()

  @doc """
  Work out which extensions a device may use, given the versions it reports.

  Returns the keys the device should attach, plus bookkeeping to pass back to
  `extension_message/3` and `extension_info/3`.
  """
  @spec extensions_join(DeviceInfo.t(), extension_versions :: map()) ::
          {[String.t()], ExtensionDispatch.extensions()}
  defdelegate extensions_join(device_info, extension_versions), to: ExtensionDispatch, as: :join

  @doc """
  Handle a `"<key>:<event>"` extension message from the device.

  `:unknown` means the device is talking about an extension it may not use, and
  should be told to detach.
  """
  @spec extension_message(ExtensionDispatch.extensions(), scoped_event :: String.t(), payload :: term()) ::
          {:ok, ExtensionDispatch.extensions(), [extension_effect()]} | :unknown
  defdelegate extension_message(extensions, scoped_event, payload), to: ExtensionDispatch, as: :message

  @doc """
  Deliver a message addressed to an extension module.

  Covers timers set on an extension's behalf as well as messages from elsewhere
  in the system. Messages for extensions that are not attached are dropped.
  """
  @spec extension_info(ExtensionDispatch.extensions(), module(), msg :: term()) ::
          {:ok, ExtensionDispatch.extensions(), [extension_effect()]}
  defdelegate extension_info(extensions, module, msg), to: ExtensionDispatch, as: :info

  @doc """
  The device has confirmed the firmware it is running is good.
  """
  @spec firmware_validated(DeviceInfo.t()) :: :ok
  def firmware_validated(device_info) do
    _ = Updates.firmware_validated(device_info)
    :ok
  end

  @doc """
  The device has told us which network interface it is connected over.

  The comparison against what we already know lives here rather than in the
  caller so that holding a device connection does not require knowing how an
  interface name maps onto a humanised one.

  Returns `:unchanged` when the report matches what we already recorded.
  """
  @spec report_network_interface(DeviceInfo.t(), interface :: String.t()) ::
          {:ok, DeviceInfo.t()} | :unchanged | :error
  def report_network_interface(device_info, interface) do
    if DeviceConnection.humanized_network_interface_name(interface) == device_info.device_network_interface do
      :unchanged
    else
      case Connections.update_network_interface(device_info.connection_ref, interface) do
        {:ok, device_connection} ->
          {:ok, %{device_info | device_network_interface: device_connection.network_interface}}

        :error ->
          :error
      end
    end
  end

  @spec status_update(device_info :: DeviceInfo.t(), status :: map()) :: :ok
  def status_update(device_info, %{"status" => "started"} = status_info) do
    firmware_update_start_telemetry(device_info, status_info)

    :ok = FirmwareUpdates.status_update("started", device_info.device_id)

    :ok
  end

  def status_update(device_info, %{"status" => status} = status_info) do
    cond do
      String.contains?(String.downcase(status), "fwup error") ->
        # a temporary hook into failed updates
        :ok = FirmwareUpdates.status_update("failed", device_info.device_id, %{"reason" => "fwup error"})

      status in ["ignored", "rescheduled", "failed"] ->
        :ok = FirmwareUpdates.status_update(status, device_info.device_id, status_info)

      true ->
        :ok = FirmwareUpdates.status_update(status, device_info.device_id, status_info)
    end

    :ok
  end

  @spec firmware_update_progress(
          device_info :: DeviceInfo.t(),
          stage :: String.t(),
          percent :: integer(),
          persist_progress :: boolean()
        ) :: :ok
  def firmware_update_progress(device_info, stage, percent, persist_progress? \\ true) do
    FirmwareUpdates.update_inflight_update(device_info.device_id, stage, percent, persist_progress?)
  end

  @spec maybe_send_archive(
          device_info :: DeviceInfo.t(),
          device_api_version :: String.t(),
          opts :: Keyword.t()
        ) :: :ok
  def maybe_send_archive(device_info, device_api_version, opts \\ [])

  def maybe_send_archive(%{deployment_id: nil}, _device_api_version, _opts), do: :ok

  def maybe_send_archive(device_info, device_api_version, opts) do
    opts = Keyword.validate!(opts, audit_log: false)
    updates_enabled = device_info.device_updates_enabled && !Updates.device_in_penalty_box?(device_info)
    version_match = Version.match?(device_api_version, ">= 2.0.0")

    if updates_enabled && version_match do
      if archive = Archives.archive_for_deployment_group(device_info.deployment_id) do
        if opts[:audit_log],
          do:
            DeviceTemplates.audit_device_archive_update_triggered(
              %Device{id: device_info.device_id, identifier: device_info.device_identifier, org_id: device_info.org_id},
              archive,
              device_info.connection_ref
            )

        broadcast(device_info, "archive", %{
          size: archive.size,
          uuid: archive.uuid,
          version: archive.version,
          description: archive.description,
          platform: archive.platform,
          architecture: archive.architecture,
          # send as an ISO8601 string so both the JSON and MessagePack serializers
          # can encode it (Msgpax has no packer for NaiveDateTime); this matches the
          # value Jason already produced for the JSON serializer.
          uploaded_at: NaiveDateTime.to_iso8601(archive.inserted_at),
          url: Archives.url(archive)
        })
      end
    end

    :ok
  end

  defp announce_online(device_info) do
    # Update the connection to say that we are fully up and running
    Connections.device_connected(device_info.connection_ref)
    # tell the orchestrator that we are online
    Deployments.deployment_device_online(device_info)
  end

  defp refresh_deployment_group(device) do
    device
    |> ManagedDeployments.verify_deployment_group_membership()
    |> ManagedDeployments.set_deployment_group()
    |> Map.put(:deployment_group, nil)
  end

  defp maybe_send_public_keys(device_info, params) do
    signing_keys =
      if Enum.any?(@public_key_types, fn type -> params[type] == "on_connect" end) do
        Accounts.fetch_firmware_signing_keys(device_info.device_id)
      else
        []
      end

    Enum.each(["fwup_public_keys", "archive_public_keys"], fn key_type ->
      with "on_connect" <- params[key_type],
           org_keys when is_list(org_keys) and org_keys != [] <- signing_keys do
        broadcast(device_info, key_type, %{keys: Enum.map(org_keys, & &1.key)})
      else
        _ -> :ok
      end
    end)

    :ok
  end

  defp maybe_clear_inflight_update(_device, %{"currently_downloading_uuid" => uuid})
       when is_binary(uuid) and byte_size(uuid) > 0, do: :ok

  defp maybe_clear_inflight_update(device, _) do
    FirmwareUpdates.clear_inflight_update(device)
    :ok
  end

  defp maybe_request_extensions(device_info, device_api_version) do
    if Version.match?(device_api_version, ">= 2.2.0"),
      do: broadcast(device_info, "extensions:get", %{})

    :ok
  end

  # Whether the device is reporting the firmware we already have on record has
  # to be decided *after* its metadata is resolved, not from a raw parameter.
  # This used to match on `nerves_fw_uuid`, which only a Nerves device sends —
  # so any other device took the "this is a new firmware" path on every single
  # join, and `firmware_update_successful/2` recorded an audit entry, telemetry
  # and an update stat each time it merely reconnected.
  defp update_firmware_metadata(%{firmware_metadata: previous_metadata} = device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params, device.product_id) do
      validation_status = fetch_validation_status(params)
      auto_revert_detected? = firmware_auto_revert_detected?(params)

      if same_firmware?(previous_metadata, metadata) do
        Devices.update_firmware_metadata(device, nil, validation_status, auto_revert_detected?)
      else
        with {:ok, device} <-
               Devices.update_firmware_metadata(
                 device,
                 metadata,
                 validation_status,
                 auto_revert_detected?
               ) do
          FirmwareUpdates.firmware_update_successful(device, previous_metadata)
        end
      end
    end
  end

  # A device with no resolvable firmware, or one we have nothing on record for,
  # is never "the same" — the first report has to be written.
  defp same_firmware?(%{uuid: uuid}, %{uuid: uuid}) when not is_nil(uuid), do: true
  defp same_firmware?(_previous, _reported), do: false

  defp fetch_validation_status(params) do
    params
    |> Map.get("meta", %{})
    |> Map.get("firmware_validated")
    |> case do
      true -> :validated
      false -> :not_validated
      nil -> :unknown
    end
  end

  defp firmware_auto_revert_detected?(params) do
    params
    |> Map.get("meta", %{})
    |> Map.get("firmware_auto_revert_detected", false)
  end

  defp firmware_update_start_telemetry(%{device_identifier: identifier}, interface_info)
       when not is_map_key(interface_info, "downloader_network_interface") do
    :telemetry.execute([:nerves_hub, :devices, :downloader_network_interface_nil], %{count: 1}, %{
      identifier: identifier
    })
  end

  defp firmware_update_start_telemetry(%{device_identifier: identifier}, %{"downloader_network_interface" => nil}) do
    :telemetry.execute([:nerves_hub, :devices, :downloader_network_interface_nil], %{count: 1}, %{
      identifier: identifier
    })
  end

  defp firmware_update_start_telemetry(%{device_identifier: identifier, device_network_interface: device_interface}, %{
         "downloader_network_interface" => downloader_interface
       }) do
    if is_nil(device_interface) or
         device_interface == DeviceConnection.humanized_network_interface_name(downloader_interface) do
      :ok
    else
      :telemetry.execute([:nerves_hub, :devices, :network_interface_mismatch], %{count: 1}, %{
        downloader_network_interface: downloader_interface,
        device_network_interface: device_interface,
        identifier: identifier
      })
    end
  end

  defp topic(%DeviceInfo{device_id: id}) do
    "device:#{id}"
  end

  defp broadcast(device_info, event, payload) do
    :ok = ChannelServer.broadcast(NervesHub.PubSub, topic(device_info), event, payload)
  end
end
