defmodule NervesHubWeb.Components.DevicePage.DetailsTab do
  use NervesHubWeb, tab_component: :details

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.Scripts
  alias NervesHubWeb.Components.HealthStatus
  alias NervesHubWeb.Components.NewUI.DeviceLocation
  alias Phoenix.Socket.Broadcast

  require Logger

  @keys_to_cleanup [
    :support_scripts,
    :firmwares,
    :update_information,
    :alarms,
    :extension_overrides,
    :deployment_groups
  ]

  def tab_params(_params, _uri, %{assigns: %{device: device}} = socket) do
    socket
    |> assign_support_scripts()
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> assign(:update_information, Devices.resolve_update(device))
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> assign(:alarms, Alarms.get_current_alarms_for_device(device))
    |> assign(:extension_overrides, extension_overrides(device, device.product))
    |> assign(:delta_available?, false)
    |> assign(:selected_firmware, "")
    |> assign_metadata()
    |> assign_deployment_groups()
    |> cont()
  end

  def cleanup(), do: @keys_to_cleanup

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

  defp assign_deployment_groups(%{assigns: %{device: %{status: :provisioned} = device}} = socket) do
    assign(socket, deployment_groups: ManagedDeployments.eligible_deployment_groups(device))
  end

  defp assign_deployment_groups(%{assigns: %{product: product}} = socket) do
    assign(socket,
      deployment_groups: ManagedDeployments.get_deployment_groups_by_product(product)
    )
  end

  def render(assigns) do
    assigns = Map.put(assigns, :auto_refresh_health, !!assigns.health_check_timer)

    ~H"""
    <div
      id="details-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="transition-all duration-500 opacity-0 tab-content phx-click-loading:opacity-50 flex items-start justify-between gap-4 p-6"
    >
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
            <div class="flex items-center gap-2">
              <div class="text-neutral-50 font-medium leading-6">Health</div>
              <HealthStatus.render device_id={@device.id} health={@device.latest_health} tooltip_position="right" />
            </div>
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
              <div :if={@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
                <span class="text-base text-emerald-500">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <div :if={@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <span :if={!@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
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
          <div class="px-4 pb-4 text-xs font-normal text-zinc-400 ">
            Learn more about
            <.link class="underline underline-offset-4 decoration-dotted hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              device health reporting.
            </.link>
          </div>
        </div>

        <div :if={Enum.empty?(@latest_metrics) && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Health</div>
          </div>
          <div class="flex pt-2 px-4 pb-4 gap-2 items-center text-nerves-gray-500">
            No device health information has been received.
          </div>
          <div class="px-4 pb-4 text-xs font-normal text-zinc-400 ">
            Learn more about
            <.link class="underline underline-offset-4 decoration-dotted hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              device health reporting.
            </.link>
          </div>
        </div>

        <div :if={@alarms && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Alarms</div>
          </div>

          <div class="flex flex-col pt-2 px-4 pb-4 gap-2">
            <div :for={{alarm, description} <- @alarms} class="flex gap-3 items-center">
              <code class="text-sm text-red-500 px-2 py-1 border border-red-500 bg-zinc-800 rounded">{alarm}</code>
              <code :if={has_description?(description)}>{description}</code>
              <span :if={!has_description?(description)} class="text-nerves-gray-500">No description</span>
            </div>
          </div>

          <div class="px-4 pb-4 text-xs font-normal text-zinc-400 ">
            Learn more about
            <.link class="underline underline-offset-4 decoration-dotted hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              alarm reporting
            </.link>
          </div>
        </div>

        <div :if={!@alarms && @product.extensions.health && @device.extensions.health} class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">No Alarms Received</div>
          </div>
          <div class="px-4 pb-4 text-xs font-normal text-zinc-400 ">
            Learn more about
            <.link class="underline underline-offset-4 decoration-dotted hover:text-neutral-50" href="https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health">
              alarm reporting
            </.link>
          </div>
        </div>

        <div class="flex flex-col pb-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            General Info
          </div>
          <div class="flex flex-col gap-3">
            <div :if={not is_nil(@device.description) && @device.description != ""} class="min-h-7 px-4 flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Description:</span>
              <span class="text-sm text-zinc-300">{@device.description}</span>
            </div>

            <div :if={@device.latest_connection && @device.latest_connection.status == :disconnected} class="min-h-7 px-4 flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Last Seen:</span>
              <span class="text-sm text-zinc-300">
                <time
                  id="connection-established-at"
                  phx-hook="UpdatingTimeAgo"
                  datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.latest_connection.disconnected_at, :second)), " ", "T")}
                >
                  {NaiveDateTime.to_string(@device.latest_connection.disconnected_at)}
                </time>
              </span>
            </div>

            <div :if={@device.latest_connection && @device.latest_connection.status != :disconnected} class="min-h-7 px-4 flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Connected:</span>
              <span class="text-sm text-zinc-300">
                <time
                  id="connection-established-at"
                  phx-hook="UpdatingTimeAgo"
                  datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.latest_connection.established_at, :second)), " ", "T")}
                >
                  {NaiveDateTime.to_string(@device.latest_connection.established_at)}
                </time>
              </span>
            </div>

            <div class="min-h-7 px-4 flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Added:</span>
              <span class="text-sm text-zinc-300">{@device.inserted_at |> NaiveDateTime.to_date() |> Date.to_string()}</span>
            </div>

            <div class="min-h-7 flex px-4 gap-4 items-center relative">
              <span class="text-sm text-nerves-gray-500">Tags:</span>
              <span :if={is_nil(@device.tags)} class="text-sm text-nerves-gray-500">No Tags</span>
              <span class="device-show-tag-gradient-mask" />
              <span :if={@device.tags} class="flex gap-1 max-w-full text-nowrap relative scrollable-inner">
                <span :for={tag <- @device.tags || []} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded">{tag}</span>
              </span>
            </div>

            <div :if={!Enum.empty?(@metadata)} class="min-h-7 flex px-4 gap-4">
              <span class="pt-1 text-sm text-nerves-gray-500">Metadata:</span>
              <span class="flex flex-col gap-1">
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
            Deployment Groups
          </div>

          <div :if={is_nil(@device.deployment_group) && Enum.empty?(@deployment_groups)} class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">No deployment groups match the devices platform and architecture.</span>
          </div>

          <div :if={@device.deployment_group} class="flex flex-col pt-2 px-4 pb-6 gap-4">
            <div class="flex pt-2 gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Assigned deployment group:</span>
              <.link
                navigate={~p"/org/#{@org}/#{@product}/deployment_groups/#{@device.deployment_group}"}
                class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
              >
                <svg class="w-1.5 h-1.5" viewBox="0 0 6 6" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <circle cx="3" cy="3" r="3" fill="#10B981" />
                </svg>
                <span class="text-xs text-zinc-300 tracking-tight" class="">{@device.deployment_group.name}</span>
              </.link>
              <button
                class="p-1 border border-red-500 rounded-full bg-zinc-800"
                data-confirm="Are you sure you want to remove the device from the deployment?"
                aria-label="Remove device from the assigned deployment group"
                type="button"
                phx-click="remove-from-deployment-group"
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
          </div>

          <div :if={@device.status == :registered && @device.deployment_id} class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">Please note: The device will be removed from the deployment group upon connection if the arch and platform don't match.</span>
          </div>

          <div :if={is_nil(@device.deployment_group) && Enum.any?(@deployment_groups)} class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <form id="set-deployment-group-form" phx-update="ignore" phx-submit="set-deployment-group" class="flex gap-2 items-center w-full">
              <div class="grow grid grid-cols-1">
                <label for="deployment_group" class="hidden">Deployment Group</label>
                <select
                  id="deployment_group"
                  name="deployment_id"
                  class="col-start-1 row-start-1 appearance-none border rounded border-zinc-600 bg-zinc-900 py-1.5 pl-3 pr-8 text-sm text-zinc-400 focus:outline focus:outline-1 focus:-outline-offset-1 focus:outline-indigo-500"
                >
                  <option value="">Select a deployment group</option>
                  <option :for={deployment_group <- @deployment_groups} value={deployment_group.id}>
                    {deployment_group.name} - ({deployment_group.firmware.platform}, {deployment_group.firmware.architecture})
                  </option>
                </select>
              </div>
              <.button type="submit" aria-label="Assign to deployment" data-confirm="Are you sure you want to add the device to the deployment group?">
                Assign
              </.button>
            </form>
          </div>

          <div :if={@update_information.update_available && @device.deployment_id} class="flex p-4 gap-4 items-center justify-between border-t border-zinc-700">
            <div class="flex flex-col">
              <span>Update available</span>
              <span class="text-sm text-nerves-gray-500">An update is available in the assigned deployment group.</span>
            </div>

            <.button phx-click="push-available-update" aria-label="Send available update" data-confirm="Are you sure you want to skip the queue?" disabled={disconnected?(@device_connection)}>
              Skip the queue
            </.button>
          </div>

          <div :if={Enum.any?(@firmwares)} class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <form id="push-update-form" phx-change="select-firmware-version" class="flex gap-2 items-center w-full">
              <div class="grow grid grid-cols-1">
                <label for="firmware" class="hidden">Firmware</label>
                <select
                  id="firmware"
                  name="uuid"
                  class="col-start-1 row-start-1 appearance-none border rounded border-zinc-600 bg-zinc-900 py-1.5 pl-3 pr-8 text-sm text-zinc-400 focus:outline focus:outline-1 focus:-outline-offset-1 focus:outline-indigo-500"
                >
                  <option value="">Select a version</option>
                  <option :for={firmware <- @firmwares} value={firmware.uuid} selected={@selected_firmware && firmware.uuid == @selected_firmware}>
                    {firmware.version} ({String.slice(firmware.uuid, 0..7)})
                  </option>
                </select>
              </div>

              <.button
                :if={@delta_available?}
                type="button"
                disabled={disconnected?(@device_connection)}
                aria-label="Send delta firmware update"
                data-confirm="Are you sure you want to send this delta firmware to the device?"
                phx-value-uuid={@selected_firmware}
                phx-click="push-delta"
              >
                Send delta update
              </.button>
              <.button
                type="button"
                disabled={disconnected?(@device_connection)}
                aria-label="Send firmware update"
                data-confirm="Are you sure you want to send this firmware to the device?"
                phx-value-uuid={@selected_firmware}
                phx-click="push-update"
              >
                Send full update
              </.button>
            </form>
          </div>
        </div>
      </div>

      <div class="w-1/2 flex flex-col gap-4">
        <div class="flex flex-col items-start rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <DeviceLocation.render
            enabled_product={@product.extensions.geo}
            enabled_device={@device.extensions.geo}
            location={extract_location_data(@device)}
            enable_location_editor={!!assigns[:enable_location_editor]}
          />
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            Support Scripts
          </div>

          <div :if={Enum.empty?(@support_scripts)} class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">No support scripts have been configured.</span>
          </div>

          <div :if={Enum.any?(@support_scripts)} class="flex flex-col pt-2 px-4 pb-6 gap-2">
            <div :for={script <- @support_scripts} class="flex flex-col gap-2">
              <div class="flex items-center gap-4">
                <span class="text-base text-zinc-300">{script.name}</span>

                <button :if={!script.running?} class="p-1 border border-green-500 rounded-full bg-zinc-800" type="button" phx-click="run-script" phx-value-id={script.id}>
                  <svg class="w-3 h-3 stroke-green-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M8 19V5L18 12L8 19Z" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>

                <svg :if={script.running?} class="mr-3 -ml-1 size-5 animate-spin text-indigo-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>

                <button :if={script.output} class="p-1 border border-red-500 rounded-full bg-zinc-800" type="button" phx-click="clear-script-output" phx-value-id={script.id}>
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
              <div :if={script.output} class="mt-2 bg-[#0e1019] rounded border border-zinc-700 p-2">
                <div id="support-script" phx-hook="SupportScriptOutput" class="overflow-x-scroll"></div>
                <div id="support-script-output" class="hidden" phx-no-format>{script.output}</div>
              </div>
            </div>
          </div>

          <div class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <.button type="link" navigate={~p"/org/#{@org}/#{@product}/scripts/new"} aria-label="Add a support script">
              <.icon name="add" />Add a support script
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def hooked_event("toggle-deployment-firmware-updates", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:toggle-updates", org_user)

    {:ok, updated_device} = Devices.toggle_automatic_updates(device, user)

    message = [
      "Firmware updates ",
      (updated_device.updates_enabled && "enabled") || "disabled",
      "."
    ]

    socket
    |> assign(:device, updated_device)
    |> put_flash(:info, Enum.join(message))
    |> halt()
  end

  def hooked_event("toggle-health-check-auto-refresh", _value, socket) do
    if timer_ref = socket.assigns.health_check_timer do
      _ = Process.cancel_timer(timer_ref)

      socket
      |> assign(:health_check_timer, nil)
      |> halt()
    else
      socket
      |> schedule_health_check_timer()
      |> halt()
    end
  end

  def hooked_event("clear-manual-location-information", _, socket) do
    {:ok, device} =
      Devices.update_device(socket.assigns.device, %{
        custom_location_coordinates: nil
      })

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Manual device location information has been cleared.")
    |> halt()
  end

  def hooked_event("enable-location-editor", _, socket) do
    socket
    |> assign(:enable_location_editor, true)
    |> put_flash(:info, "Please use the map to search and pin your devices location.")
    |> halt()
  end

  def hooked_event("discard-location-changes", _, socket) do
    socket
    |> assign(:enable_location_editor, false)
    |> halt()
  end

  def hooked_event("update-device-location", latlng, socket) do
    socket
    |> assign(:buffer_custom_location, latlng)
    |> halt()
  end

  def hooked_event("save-location-changes", _, socket) do
    {:ok, device} =
      Devices.update_device(socket.assigns.device, %{
        custom_location_coordinates: [
          socket.assigns.buffer_custom_location["lat"],
          socket.assigns.buffer_custom_location["lng"]
        ]
      })

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Custom location coordinates saved.")
    |> assign(:enable_location_editor, false)
    |> halt()
  end

  def hooked_event("set-deployment-group", %{"deployment_id" => ""}, socket) do
    socket
    |> put_flash(:error, "Please select a deployment group.")
    |> halt()
  end

  def hooked_event("set-deployment-group", %{"deployment_id" => deployment_id}, socket) do
    %{user: user, device: device, deployment_groups: deployment_groups} = socket.assigns

    authorized!(:"device:set-deployment-group", socket.assigns.org_user)

    deployment = Enum.find(deployment_groups, &(&1.id == String.to_integer(deployment_id)))
    device = Devices.update_deployment_group(device, deployment)
    _ = DeviceTemplates.audit_device_deployment_group_update(user, device, deployment)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Device successfully added to Deployment Group.")
    |> halt()
  end

  def hooked_event("push-available-update", _, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{device: device, user: user} = socket.assigns

    deployment_group = NervesHub.Repo.preload(device.deployment_group, [:firmware, :org])

    case Devices.told_to_update(device, deployment_group) do
      {:ok, _inflight_update} ->
        DeviceTemplates.audit_pushed_available_update(user, device, deployment_group)

        socket
        |> put_flash(:info, "Pushing available firmware update.")
        |> halt()

      :error ->
        Logger.error(
          "An inflight update could not be created or found for the device #{device.identifier} (#{device.id})"
        )

        socket
        |> put_flash(
          :info,
          "There was an error sending the update to the device. Please contact support."
        )
        |> halt()
    end
  end

  def hooked_event("select-firmware-version", %{"uuid" => ""}, socket) do
    socket
    |> halt()
  end

  def hooked_event("select-firmware-version", %{"uuid" => uuid}, socket) do
    %{product: product, device: device} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

    firmware_delta_updatable? = Devices.delta_updatable?(device, firmware)
    delta_complete? = Devices.delta_ready?(device, firmware)

    socket
    |> assign(:delta_available?, firmware_delta_updatable? && delta_complete?)
    |> assign(:selected_firmware, uuid)
    |> halt()
  end

  def hooked_event("push-update", %{"uuid" => uuid}, socket) when uuid == "" do
    socket
    |> put_flash(:error, "Please select a firmware version to send to the device.")
    |> halt()
  end

  def hooked_event("push-update", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{product: product, device: device, user: user, org: org} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

    Logger.info("Manually sending full firmware",
      firmware_uuid: firmware.uuid,
      device_identifier: device.identifier
    )

    opts =
      if proxy_url = get_in(org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    {:ok, device} = DeviceEvents.manual_update(device, firmware, user, opts)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Firmware update request requested.")
    |> halt()
  end

  def hooked_event("push-delta", %{"uuid" => uuid}, socket) when uuid == "" do
    socket
    |> put_flash(:error, "Please select a firmware version to send to the device.")
    |> halt()
  end

  def hooked_event("push-delta", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{product: product, device: device, user: user, org: org} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

    Logger.info(
      "Manually sending firmware delta",
      source_uuid: device.firmware_metadata.uuid,
      target_uuid: firmware.uuid,
      device_identifier: device.identifier
    )

    opts =
      if proxy_url = get_in(org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    {:ok, device} = DeviceEvents.manual_update(device, firmware, user, opts ++ [delta: true])

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Sending firmware update request.")
    |> halt()
  end

  def hooked_event("remove-from-deployment-group", _, %{assigns: %{device: device}} = socket) do
    device = Devices.clear_deployment_group(device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Device successfully removed from the deployment group")
    |> halt()
  end

  def hooked_event("run-script", %{"id" => id}, socket) do
    %{assigns: %{device: device, support_scripts: scripts, org_user: org_user}} = socket

    authorized!(:"support_script:run", org_user)

    script = Enum.find(scripts, fn script -> script.id == String.to_integer(id) end)

    socket
    |> start_async({:run_script, id}, fn -> Scripts.Runner.send(device, script) end)
    |> assign(:support_scripts, update_script(scripts, id, %{output: nil, running?: true}))
    |> halt()
  end

  def hooked_event("clear-script-output", %{"id" => id}, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    socket
    |> assign(:support_scripts, update_script(scripts, id, %{output: nil, running?: false}))
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(:platform_or_architecture_updated, %{assigns: %{device: device}} = socket) do
    assign(socket, :firmwares, Firmwares.get_firmware_for_device(device))
    |> halt()
  end

  def hooked_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/created", payload: %{firmware: new_firmware}},
        socket
      ) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)

    socket
    |> assign(:firmwares, firmware)
    |> put_flash(
      :notice,
      "New firmware #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)}) is available for selection"
    )
    |> halt()
  end

  def hooked_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: deleted_firmware}},
        socket
      ) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)

    socket
    |> assign(:firmwares, firmware)
    |> put_flash(
      :notice,
      "Firmware #{deleted_firmware.version} (#{String.slice(deleted_firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> halt()
  end

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    socket
    |> assign(:latest_metrics, latest_metrics)
    |> assign_metadata()
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def hooked_async({:run_script, id}, result, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    output =
      case result do
        {:ok, {:ok, output}} ->
          output

        {:ok, {:error, reason}} ->
          "Error: #{reason}"

        e ->
          inspect(e)
      end

    scripts = update_script(scripts, id, %{output: output, running?: false})

    socket
    |> assign(:support_scripts, scripts)
    |> halt()
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  defp schedule_health_check_timer(socket) do
    %{device: device, product: product} = socket.assigns

    if connected?(socket) and health_extension_enabled?(product, device) do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end

  defp health_extension_enabled?(product, device) do
    product.extensions.health and device.extensions.health
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

  defp extract_location_data(%{custom_location_coordinates: coordinates}) when not is_nil(coordinates) do
    %{
      "latitude" => List.first(coordinates),
      "longitude" => List.last(coordinates),
      "source" => "manual"
    }
  end

  defp extract_location_data(%Device{latest_connection: connection}) when not is_nil(connection) do
    connection.metadata["location"]
  end

  defp extract_location_data(_), do: %{}

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do: firmware_metadata |> Map.keys() |> Enum.map(&to_string/1)

  defp has_description?(description) do
    is_binary(description) and byte_size(description) > 0 and description != "[]"
  end
end
