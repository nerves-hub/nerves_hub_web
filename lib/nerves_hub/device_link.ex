defmodule NervesHub.DeviceLink do
  @moduledoc """
  Encapsulation of device connection workflow logic
  """

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments
  alias Phoenix.Channel.Server, as: ChannelServer

  defmodule DeviceInfo do
    defstruct [
      :allowed_extensions,
      :connection_ref,
      :deployment_id,
      :device_id,
      :device_identifier,
      :device_network_interface,
      :device_updates_blocked_until,
      :device_updates_enabled,
      :firmware_metadata,
      :org_id,
      :product_id
    ]

    @type t :: %__MODULE__{
            allowed_extensions: list(atom()) | nil,
            connection_ref: String.t() | nil,
            deployment_id: pos_integer() | nil,
            device_id: pos_integer() | nil,
            device_updates_enabled: boolean() | nil,
            device_updates_blocked_until: DateTime.t() | nil,
            device_identifier: String.t() | nil,
            device_network_interface: String.t() | nil,
            firmware_metadata: map() | nil,
            org_id: pos_integer() | nil,
            product_id: pos_integer() | nil
          }
  end

  @public_key_types ["fwup_public_keys", "archive_public_keys"]

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
    updates_enabled = device_info.device_updates_enabled && !Devices.device_in_penalty_box?(device_info)
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
          uploaded_at: archive.inserted_at,
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
    Devices.deployment_device_online(device_info)
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
        Devices.fetch_firmware_signing_keys(device_info.device_id)
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

  # The reported firmware is the same as what we already know about
  defp update_firmware_metadata(
         %Device{firmware_metadata: %{uuid: uuid}} = device,
         %{"nerves_fw_uuid" => uuid} = params
       ) do
    validation_status = fetch_validation_status(params)
    auto_revert_detected? = firmware_auto_revert_detected?(params)

    Devices.update_firmware_metadata(device, nil, validation_status, auto_revert_detected?)
  end

  # A new UUID is being reported from an update
  defp update_firmware_metadata(%{firmware_metadata: previous_metadata} = device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params, device.product_id),
         validation_status = fetch_validation_status(params),
         auto_revert_detected? = firmware_auto_revert_detected?(params),
         {:ok, device} <-
           Devices.update_firmware_metadata(
             device,
             metadata,
             validation_status,
             auto_revert_detected?
           ) do
      FirmwareUpdates.firmware_update_successful(device, previous_metadata)
    end
  end

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
