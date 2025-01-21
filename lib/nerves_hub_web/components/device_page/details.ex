defmodule NervesHubWeb.Components.DevicePage.Details do
  use NervesHubWeb, :live_component

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Templates
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Scripts

  alias NervesHub.Repo

  alias NervesHubWeb.Components.NewUI.DeviceLocation

  def update(%{latest_metrics: latest_metrics}, socket) do
    socket
    |> assign(:latest_metrics, latest_metrics)
    |> assign_metadata()
    |> ok()
  end

  def update(%{firmwares: firmware}, socket) do
    socket
    |> assign(:firmwares, firmware)
    |> send_toast(:info, "New firmware available for selection")
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:device, Repo.preload(assigns.device, :deployment))
    |> assign_support_scripts()
    |> assign(:eligible_deployments, Deployments.eligible_deployments(assigns.device))
    |> assign(:firmwares, Firmwares.get_firmware_for_device(assigns.device))
    |> assign(:update_information, Devices.resolve_update(assigns.device))
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(assigns.device.id))
    |> assign(:alarms, Alarms.get_current_alarms_for_device(assigns.device))
    |> assign(:extension_overrides, extension_overrides(assigns.device, assigns.product))
    |> assign_metadata()
    |> ok()
  end

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    health = Devices.get_latest_health(device.id)

    metadata =
      if health, do: health.data["metadata"] || %{}, else: %{}

    assign(socket, :metadata, Map.drop(metadata, standard_keys(device)))
  end

  defp assign_support_scripts(socket) do
    scripts =
      socket.assigns.product
      |> Scripts.all_by_product()
      |> Enum.map(&Map.merge(&1, %{output: nil, running?: false}))

    assign(socket, :support_scripts, scripts)
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-4 p-6">
      <div class="w-1/2 flex flex-col gap-4">
        <div :if={!@product.extensions.health || !@device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Health and Alerting</div>
          </div>
          <div class="flex pt-2 px-4 pb-4 gap-2 items-center text-nerves-gray-500">
            Reporting is not enabled {if(!@product.extensions.health, do: "for your product", else: "for your device")}.
          </div>
          <div class="px-4 pb-4">
            <.link class="text-xs font-normal text-zinc-400 hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              Learn more about device health and alert reporting.
            </.link>
          </div>
        </div>

        <div :if={Enum.any?(@latest_metrics) && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Health</div>
            <div class="flex items-center gap-2">
              <div class="text-xs text-nerves-gray-500 tracking-wide">
                <span>Last updated: </span>
                <time id="health-last-updated" phx-hook="UpdatingTimeAgo" datetime={String.replace(DateTime.to_string(DateTime.truncate(@latest_metrics["timestamp"], :second)), " ", "T")}>
                  {Timex.from_now(@latest_metrics["timestamp"])}
                </time>
              </div>
              <div class="text-xs text-zinc-300 tracking-wide">Auto refresh</div>
              <div>
                <button
                  type="button"
                  phx-click="toggle-health-check-auto-refresh"
                  class={[
                    "relative inline-flex items-center h-3.5 w-6 shrink-0 cursor-pointer rounded-full border-1.5 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:ring-offset-2",
                    (@auto_refresh_health && "bg-indigo-500") || "bg-gray-200"
                  ]}
                  role="switch"
                  aria-checked="false"
                >
                  <span class="sr-only">Auto refresh health information</span>
                  <span
                    aria-hidden="true"
                    class={[
                      "pointer-events-none inline-block size-3",
                      (@auto_refresh_health && "translate-x-3") || "translate-x-0",
                      "transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
                    ]}
                  >
                  </span>
                </button>
              </div>
            </div>
          </div>
          <div class="flex pt-2 px-4 pb-4 gap-2 items-center justify-items-stretch flex-wrap">
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-emerald-500 bg-health-good">
              <span class="text-xs text-zinc-400 tracking-wide">CPU</span>
              <div :if={@latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
                <span class="text-base text-emerald-500">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <span :if={!@latest_metrics["cpu_temp"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
            </div>
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-amber-500 bg-health-warning">
              <span class="text-xs text-zinc-400 tracking-wide">Memory used</span>
              <div :if={@latest_metrics["mem_used_mb"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["mem_used_mb"])}MB</span>
                <span class="text-base text-amber-500">{round(@latest_metrics["mem_used_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["mem_used_mb"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-nerves-gray-500">Not reported</span>
              </div>
            </div>
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-indigo-500 bg-health-neutral">
              <span class="text-xs text-zinc-400 tracking-wide">Load avg</span>
              <div :if={@latest_metrics["load_1min"] || @latest_metrics["load_5min"] || @latest_metrics["load_15min"]} class="flex justify-between items-center">
                <span :if={@latest_metrics["load_1min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_1min"]}</span>
                <span :if={!@latest_metrics["load_1min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
                <span class="w-px h-4 bg-zinc-700"></span>
                <span :if={@latest_metrics["load_5min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_5min"]}</span>
                <span :if={!@latest_metrics["load_5min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
                <span class="w-px h-4 bg-zinc-700"></span>
                <span :if={@latest_metrics["load_15min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_15min"]}</span>
                <span :if={!@latest_metrics["load_15min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
              </div>
              <div :if={!@latest_metrics["load_1min"] && !@latest_metrics["load_5min"] && !@latest_metrics["load_15min"]} class="flex items-center">
                <span class="text-xl leading-[30px] text-nerves-gray-500">Not reported</span>
              </div>
            </div>
          </div>
          <div class="px-4 pb-4">
            <.link class="text-xs font-normal text-zinc-400 hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              Learn more about device health reporting.
            </.link>
          </div>
        </div>

        <div :if={Enum.empty?(@latest_metrics) && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Health</div>
          </div>
          <div class="flex pt-2 px-4 pb-4 gap-2 items-center">
            No device health information has been received.
          </div>
          <div class="px-4 pb-4">
            <.link class="text-xs font-normal text-zinc-400 hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              Learn more about device health reporting.
            </.link>
          </div>
        </div>

        <div :if={@alarms && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Alarms</div>
          </div>

          <div class="flex pt-2 px-4 pb-4 gap-2 items-center">
            <div :for={{alarm, description} <- @alarms}>
              <div class="flex gap-3 items-center">
                <code class="text-sm text-red-500 px-2 py-1 border border-red-500 bg-zinc-800 rounded">{alarm}</code>
                <code :if={has_description?(description)}>{description}</code>
              </div>
            </div>
          </div>

          <div class="px-4 pb-4">
            <.link class="text-xs font-normal text-zinc-400 hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              Learn more about alarm reporting.
            </.link>
          </div>
        </div>

        <div :if={!@alarms && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">No Alarms Received</div>
          </div>
          <div class="px-4 pb-4">
            <.link class="text-xs font-normal text-zinc-400 hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-alarms">
              Learn more about alarm reporting.
            </.link>
          </div>
        </div>

        <div class="flex flex-col pb-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            General info
          </div>
          <div class="flex flex-col gap-3">
            <div :if={@device.description != ""} class="min-h-7 px-4 flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Description:</span>
              <span class="text-sm text-zinc-300">{@device.description}</span>
            </div>

            <div class="min-h-7 flex px-4 gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Tags:</span>
              <span :if={is_nil(@device.tags)} class="text-sm text-nerves-gray-500">No Tags</span>
              <span :if={@device.tags} class="flex gap-1">
                <span :for={tag <- @device.tags || []} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded">{tag}</span>
              </span>
            </div>

            <div :if={!Enum.empty?(@metadata)} class="min-h-7 flex px-4 gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Metadata:</span>
              <span class="flex gap-1">
                <span :for={{key, value} <- Map.filter(@metadata, fn {_key, val} -> val != "" end)} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded">
                  <span>{key |> String.replace("_", " ") |> String.capitalize()}: {value}</span>
                </span>
              </span>
            </div>

            <div :if={@extension_overrides != []} class="flex min-h-7 px-4 gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Disabled extensions:</span>
              <span class="flex gap-1">
                <span :for={extension <- @extension_overrides} class="text-sm text-red-500 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded" class="">{extension}</span>
              </span>
            </div>
          </div>
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            Deployments
          </div>

          <div class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">Assigned deployment:</span>
            <span :if={is_nil(@device.deployment)} class="text-sm text-nerves-gray-500">No assigned deployment</span>
            <.link
              :if={@device.deployment}
              navigate={~p"/org/#{@org.name}/#{@product.name}/deployments/#{@device.deployment.name}"}
              class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
            >
              <svg class="w-1.5 h-1.5" viewBox="0 0 6 6" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="3" cy="3" r="3" fill="#10B981" />
              </svg>
              <span class="text-xs text-zinc-300 tracking-tight" class="">{@device.deployment.name}</span>
            </.link>

            <button
              :if={@device.deployment}
              class="p-1 border border-red-500 rounded-full bg-zinc-800"
              data-confirm="Are you sure you want to remove the device from the deployment?"
              aria-label="Remove device from the assigned deployment"
              type="button"
              phx-target={@myself}
              phx-click="remove-from-deployment"
            >
              <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke="#EF4444"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </button>
          </div>

          <div :if={is_nil(@device.deployment) && Enum.any?(@eligible_deployments)} class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <form phx-target={@myself} phx-submit="set-deployment" class="flex gap-2 items-center w-full">
              <div class="grow grid grid-cols-1">
                <select
                  name="deployment_id"
                  class="col-start-1 row-start-1 appearance-none border rounded border-zinc-600 bg-zinc-900 py-1.5 pl-3 pr-8 text-sm text-zinc-400 focus:outline focus:outline-1 focus:-outline-offset-1 focus:outline-indigo-500"
                >
                  <option value="">Select a deployment</option>
                  <option :for={deployment <- @eligible_deployments} value={deployment.id}>{deployment.name}</option>
                </select>
              </div>
              <button
                class="box-content h-5 py-1.5 px-3 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-300 disabled:text-zinc-500"
                aria-label="Add to deployment"
                data-confirm="Are you sure you want to add the device to the deployment?"
              >
                Add to deployment
              </button>
            </form>
            <div>
              <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M10 12.5V10M10 7.5V7.49167M17.5 10C17.5 14.1421 14.1421 17.5 10 17.5C5.85786 17.5 2.5 14.1421 2.5 10C2.5 5.85786 5.85786 2.5 10 2.5C14.1421 2.5 17.5 5.85786 17.5 10Z"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </div>
          </div>

          <div :if={@update_information.update_available && @device.deployment_id} class="flex p-4 gap-4 items-center justify-between border-t border-zinc-700">
            <div class="flex flex-col">
              <span>Update available</span>
              <span class="text-sm text-nerves-gray-500">An update is available in the assigned deployment.</span>
            </div>

            <button
              phx-target={@myself}
              phx-submit="push-available-update"
              class="box-content h-5 py-1.5 px-3 mr-9 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-300 disabled:text-zinc-500"
              aria-label="Send available update"
              data-confirm="Are you sure?"
              disabled={disconnected?(@device_connection)}
            >
              Skip the queue
            </button>
          </div>

          <div class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <form :if={Enum.any?(@firmwares)} phx-target={@myself} phx-submit="push-update" class="flex gap-2 items-center w-full">
              <div class="grow grid grid-cols-1">
                <select
                  id="firmware"
                  name="uuid"
                  class="col-start-1 row-start-1 appearance-none border rounded border-zinc-600 bg-zinc-900 py-1.5 pl-3 pr-8 text-sm text-zinc-400 focus:outline focus:outline-1 focus:-outline-offset-1 focus:outline-indigo-500"
                >
                  <option value="">Select a version</option>
                  <option :for={firmware <- @firmwares} value={firmware.uuid}>{firmware.version}</option>
                </select>
              </div>
              <button
                class="box-content h-5 py-1.5 px-3 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-300 disabled:text-zinc-500"
                disabled={disconnected?(@device_connection)}
                aria-label="Send firmware update"
                data-confirm="Are you sure?"
              >
                Send update
              </button>
            </form>
            <div>
              <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M10 12.5V10M10 7.5V7.49167M17.5 10C17.5 14.1421 14.1421 17.5 10 17.5C5.85786 17.5 2.5 14.1421 2.5 10C2.5 5.85786 5.85786 2.5 10 2.5C14.1421 2.5 17.5 5.85786 17.5 10Z"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <div class="w-1/2 flex flex-col gap-4">
        <div class="flex flex-col items-start rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <DeviceLocation.render enabled_product={@product.extensions.geo} enabled_device={@device.extensions.geo} location={@device.connection_metadata["location"]} />
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            Support Scripts
          </div>

          <div :if={Enum.empty?(@support_scripts)} class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">No support scripts have been configured.</span>
          </div>

          <div :if={Enum.any?(@support_scripts)} class="flex-col pt-2 px-4 pb-6 gap-4 items-center">
            <div :for={script <- @support_scripts} class="flex flex-col gap-2">
              <div class="flex gap-4">
                <span class="text-base text-zinc-300">{script.name}</span>

                <button
                  :if={!disconnected?(@device_connection)}
                  class="p-1 border border-green-500 rounded-full bg-zinc-800"
                  type="button"
                  disabled={script.running?}
                  phx-target={@myself}
                  phx-click="run-script"
                  phx-value-id={script.id}
                >
                  <svg class="w-3 h-3 stroke-green-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M8 19V5L18 12L8 19Z" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>

                <button :if={script.output} class="p-1 border border-red-500 rounded-full bg-zinc-800" type="button" phx-target={@myself} phx-click="clear-script-output" phx-value-id={script.id}>
                  <svg class="size-3 stroke-red-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path
                      d="M8 8H16M16 12H8M8 16H12M20 13V6C20 4.89543 19.1046 4 18 4H6C4.89543 4 4 4.89543 4 6V18C4 19.1046 4.89543 20 6 20H13M19 19L21 17M19 19L17 17M19 19L21 21M19 19L17 21"
                      stroke-width="1.2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </button>
              </div>
              <div :if={script.output} class="mt-2">
                <code class="p-3 bg-zinc-800">{script.output}</code>
              </div>
            </div>
          </div>

          <div class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <.link navigate={~p"/org/#{@org.name}/#{@product.name}/scripts"} class="box-content h-5 py-1.5 px-3 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-300">
              Add a support script
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("set-deployment", %{"deployment_id" => deployment_id}, socket) do
    %{user: user, device: device, eligible_deployments: eligible_deployments} = socket.assigns

    authorized!(:"device:set-deployment", socket.assigns.org_user)

    deployment = Enum.find(eligible_deployments, &(&1.id == String.to_integer(deployment_id)))
    device = Devices.update_deployment(device, deployment)
    _ = Templates.audit_device_deployment_update(user, device, deployment)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> send_toast(:info, "Device successfully added to Deployment.")
    |> noreply()
  end

  def handle_event("push-available-update", _, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{device: device, deployment: deployment, user: user} = socket.assigns

    deployment = NervesHub.Repo.preload(deployment, :firmware)

    description =
      "#{user.name} pushed available firmware update #{deployment.firmware.version} #{deployment.firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)

    case Devices.told_to_update(device, deployment) do
      {:ok, inflight_update} ->
        _ =
          NervesHubWeb.Endpoint.broadcast(
            "device:#{device.id}",
            "deployments/update",
            inflight_update
          )

        socket
        |> send_toast(:info, "Pushing available firmware update.")
        |> noreply()

      :error ->
        Logger.error(
          "An inflight update could not be created or found for the device #{device.identifier} (#{device.id})"
        )

        socket
        |> send_toast(
          :info,
          "There was an error sending the update to the device. Please contact support."
        )
        |> noreply()
    end
  end

  def handle_event("push-update", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{product: product, device: device, user: user} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)
    {:ok, url} = Firmwares.get_firmware_url(firmware)
    {:ok, meta} = Firmwares.metadata_from_firmware(firmware)
    {:ok, device} = Devices.disable_updates(device, user)

    description =
      "User #{user.name} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)

    payload = %UpdatePayload{
      update_available: true,
      firmware_url: url,
      firmware_meta: meta
    }

    _ = NervesHubWeb.Endpoint.broadcast("device:#{device.id}", "devices/update-manual", payload)

    socket
    |> assign(:device, device)
    |> send_toast(:info, "Sending firmware update request.")
    |> noreply()
  end

  def handle_event("remove-from-deployment", _, %{assigns: %{device: device}} = socket) do
    device = Devices.clear_deployment(device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> send_toast(:info, "Device successfully removed from the deployment")
    |> noreply()
  end

  def handle_event("run-script", %{"id" => id}, socket) do
    %{assigns: %{device: device, support_scripts: scripts, org_user: org_user}} = socket

    authorized!(:"support_script:run", org_user)

    script = Enum.find(scripts, fn script -> script.id == String.to_integer(id) end)

    socket
    |> assign(:support_scripts, update_script(scripts, id, %{running?: true}))
    |> start_async({:run_script, id}, fn -> Scripts.Runner.send(device, script) end)
    |> noreply()
  end

  def handle_event("clear-script-output", %{"id" => id}, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    socket
    |> assign(:support_scripts, update_script(scripts, id, %{output: nil, running?: false}))
    |> noreply()
  end

  def handle_async({:run_script, id}, result, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    output =
      case result do
        {:ok, output} ->
          output

        e ->
          inspect(e)
      end

    scripts = update_script(scripts, id, %{output: output, running?: false})

    socket
    |> assign(:support_scripts, scripts)
    |> noreply()
  end

  defp update_script(scripts, id, new_info) when is_binary(id) do
    update_script(scripts, String.to_integer(id), new_info)
  end

  defp update_script(scripts, id, new_info) do
    index = Enum.find_index(scripts, fn script -> script.id == id end)

    List.update_at(scripts, index, fn script ->
      Map.merge(script, new_info)
    end)
  end

  # TODO: this is duplicated code, find a new way to reuse it
  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end

  defp extension_overrides(device, product) do
    device.extensions
    |> Map.from_struct()
    |> Enum.filter(fn {extension, enabled} ->
      enabled == false and product.extensions[extension]
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do:
      firmware_metadata
      |> Map.keys()
      |> Enum.map(&to_string/1)

  defp has_description?(description) do
    is_binary(description) and byte_size(description) > 0
  end
end
