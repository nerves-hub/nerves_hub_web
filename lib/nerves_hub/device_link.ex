defmodule NervesHub.DeviceLink do
  @moduledoc """
  Encapsulation of device connection workflow logic
  """

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias Phoenix.Channel.Server, as: ChannelServer

  require Logger

  @spec join(Device.t(), connection_reference :: String.t(), params :: map()) ::
          {:ok, Device.t()} | {:error, any()}
  def join(device, ref_id, params) do
    with {:ok, device} <- update_firmware_metadata(device, params),
         :ok <-
           update_connection_metadata(ref_id, %{
             "device_api_version" => params["device_api_version"]
           }),
         :ok <- maybe_clear_inflight_update(device, params) do
      device = refresh_deployment_group(device)
      {:ok, device}
    else
      err -> {:error, err}
    end
  end

  @spec after_join(Device.t(), connection_reference :: String.t(), params :: map()) ::
          :ok | {:error, any()}
  def after_join(device, reference_id, params) do
    with :ok <- maybe_send_public_keys(device, params),
         :ok <- maybe_send_archive(device, params["device_api_version"], reference_id),
         :ok <- maybe_request_extensions(device, params["device_api_version"]),
         :ok <- maybe_update_device_network_interface(device, params["network_interface"]) do
      announce_online(device, reference_id)
    end
  rescue
    err -> {:error, err}
  end

  @spec update_connection_metadata(reference_id :: String.t(), metadata :: map()) :: :ok
  def update_connection_metadata(reference_id, metadata) do
    :ok = Connections.merge_update_metadata(reference_id, metadata)
  end

  @spec status_update(device :: Device.t(), status :: String.t(), update_started? :: boolean()) ::
          :ok
  def status_update(device, status, update_started?) do
    # a temporary hook into failed updates
    if String.contains?(String.downcase(status), "fwup error") do
      # if there was an error during updating
      # mark the attempt
      _ =
        if update_started? do
          Devices.update_attempted(device)
        end

      # clear the inflight update
      Devices.clear_inflight_update(device)
      :ok
    else
      # if there was no error during updating, do nothing
      :ok
    end
  end

  @spec firmware_update_progress(device :: Device.t(), percent :: integer()) :: :ok
  def firmware_update_progress(device, percent) do
    topic = "device:#{device.identifier}:internal"

    :ok =
      ChannelServer.broadcast_from!(NervesHub.PubSub, self(), topic, "fwup_progress", %{
        device_id: device.id,
        percent: percent
      })
  end

  @spec maybe_send_archive(
          device :: Device.t(),
          device_api_version :: String.t(),
          reference_id :: String.t(),
          opts :: Keyword.t()
        ) :: :ok
  def maybe_send_archive(device, device_api_version, reference_id, opts \\ [])

  def maybe_send_archive(%{deployment_id: nil}, _device_api_version, _reference_id, _opts), do: :ok

  def maybe_send_archive(device, device_api_version, reference_id, opts) do
    opts = Keyword.validate!(opts, audit_log: false)
    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)
    version_match = Version.match?(device_api_version, ">= 2.0.0")

    if updates_enabled && version_match do
      if archive = Archives.archive_for_deployment_group(device.deployment_id) do
        if opts[:audit_log],
          do:
            DeviceTemplates.audit_device_archive_update_triggered(
              device,
              archive,
              reference_id
            )

        broadcast(device, "archive", %{
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

  defp announce_online(device, reference_id) do
    # Update the connection to say that we are fully up and running
    Connections.device_connected(device, reference_id)
    # tell the orchestrator that we are online
    Devices.deployment_device_online(device)
  end

  defp refresh_deployment_group(device) do
    device
    |> ManagedDeployments.verify_deployment_group_membership()
    |> ManagedDeployments.set_deployment_group()
    |> Map.put(:deployment_group, nil)
  end

  defp maybe_send_public_keys(device, params) do
    Enum.each(["fwup_public_keys", "archive_public_keys"], fn key_type ->
      if params[key_type] == "on_connect" do
        org_keys = NervesHub.Accounts.list_org_keys(device.org_id, false)

        broadcast(device, key_type, %{keys: Enum.map(org_keys, & &1.key)})
      end
    end)

    :ok
  end

  defp maybe_clear_inflight_update(_device, %{"currently_downloading_uuid" => uuid})
       when is_binary(uuid) and byte_size(uuid) > 0,
       do: :ok

  defp maybe_clear_inflight_update(device, _) do
    Devices.clear_inflight_update(device)
    :ok
  end

  defp maybe_request_extensions(device, device_api_version) do
    if Version.match?(device_api_version, ">= 2.2.0"),
      do: broadcast(device, "extensions:get", %{})

    :ok
  end

  defp maybe_update_device_network_interface(_device, nil), do: :ok

  defp maybe_update_device_network_interface(device, network_interface) do
    if Device.friendly_network_interface_name(network_interface) == device.network_interface do
      :ok
    else
      case Devices.update_network_interface(device, network_interface) do
        {:ok, _device} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "[DeviceChannel] could not update device network interface because: #{inspect(changeset.errors)}"
          )

          :ok
      end
    end
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
      Devices.firmware_update_successful(device, previous_metadata)
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

  defp topic(%Device{id: id}) do
    "device:#{id}"
  end

  defp broadcast(device, event, payload) do
    :ok = ChannelServer.broadcast(NervesHub.PubSub, topic(device), event, payload)
  end
end
