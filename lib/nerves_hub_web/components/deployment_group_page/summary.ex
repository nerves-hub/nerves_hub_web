defmodule NervesHubWeb.Components.DeploymentGroupPage.Summary do
  use NervesHubWeb, :live_component

  alias NervesHub.Devices

  def update(%{update_inflight_info: true}, socket) do
    deployment_group = socket.assigns.deployment_group

    inflight_updates = Devices.inflight_updates_for(deployment_group)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, Devices.updating_count(deployment_group))
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col items-start gap-4 p-6">
      <div :if={@waiting_for_update_count == 0} class="w-full p-4 items-center justify-center rounded border border-zinc-700 bg-zinc-900">
        <div class="flex text-xl text-neutral-50 font-medium leading-6 h-10 justify-center items-center">All devices are up to date!</div>
      </div>

      <div :if={@waiting_for_update_count > 0} class="w-full h-24 box-content flex items-center justify-center rounded border border-zinc-700 bg-zinc-900">
        <div class="relative sticky top-0 w-full items-center justify-center rounded overflow-visible z-20">
          <div class="z-40 absolute -top-px border-t rounded-tl border-success-500" role="progressbar" style={"width: #{deployment_group_percentage(@up_to_date_count, @deployment_group)}%"}>
            <div class="animate-pulse bg-progress-glow w-full h-16" />
          </div>

          <div class="flex flex-col gap-1 items-center justify-center my-1 py-2 px-2 bg-base-900/20 text-sm font-medium">
            <div class="text-base">{deployment_group_percentage(@up_to_date_count, @deployment_group)}% of devices updated</div>
            <div>{@updating_count} device(s) updating - {@waiting_for_update_count} device(s) waiting</div>
          </div>
        </div>
      </div>

      <div class="size-full flex gap-4">
        <div class="w-1/2 flex flex-col gap-4">
          <div class="flex flex-col gap-2 p-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
            <div class="h-9 flex items-start justify-between">
              <div class="text-neutral-50 font-medium leading-6">Current Release</div>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-16">Firmware:</span>

              <.link
                navigate={~p"/org/#{@org.name}/#{@product.name}/firmware/#{@deployment_group.firmware.uuid}"}
                class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
              >
                <span class="text-xs text-zinc-300 tracking-tight">{@deployment_group.firmware.version} ({String.slice(@deployment_group.firmware.uuid, 0..7)})</span>
              </.link>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-16">Archive:</span>

              <.link
                :if={@deployment_group.archive}
                navigate={~p"/org/#{@org.name}/#{@product.name}/archives/#{@deployment_group.archive.uuid}"}
                class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
              >
                <span class="text-xs text-zinc-300 tracking-tight">{@deployment_group.archive.version} ({String.slice(@deployment_group.archive.uuid, 0..7)})</span>
              </.link>
              <span :if={is_nil(@deployment_group.archive)} class="pl-1 text-xs text-nerves-gray-500">No archive configured</span>
            </div>
          </div>

          <div class="flex flex-col gap-2 p-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
            <div class="h-9 flex items-start justify-between">
              <div class="text-neutral-50 font-medium leading-6">Inflight updates</div>
            </div>
            <div class="flex flex-col gap-3">
              <div :if={@inflight_updates == []} class="flex gap-4 items-center">
                <span class="text-sm text-nerves-gray-500">No devices are currently updating</span>
              </div>
              <div :if={@inflight_updates != []} class="flex gap-4 items-center">
                <span class="text-sm text-nerves-gray-500"><span class="font-semibold">{Enum.count(@inflight_updates)}</span> device(s) are currently updating</span>
              </div>
              <div :for={inflight_update <- @inflight_updates} :if={@inflight_updates != []} class="flex gap-4 items-center">
                <span class="flex h-7 py-1 px-2 items-center rounded bg-zinc-800 text-base-300">
                  <.link navigate={~p"/org/#{@org.name}/#{@product.name}/devices/#{inflight_update.device.identifier}"}>
                    {inflight_update.device.identifier}
                  </.link>
                </span>
              </div>
            </div>
          </div>
        </div>
        <div class="w-1/2 flex flex-col gap-4">
          <div class="flex flex-col gap-2 p-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
            <div class="h-9 flex items-start justify-between">
              <div class="text-neutral-50 font-medium leading-6">Settings Overview</div>
            </div>

            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Concurrent device updates:</span>
              <span class="text-sm text-zinc-300">{@deployment_group.concurrent_updates}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Minutes before expiring updates:</span>
              <span class="text-sm text-zinc-300">{@deployment_group.inflight_update_expiration_minutes}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Failure rate:</span>
              <span class="text-sm text-zinc-300">
                <span class="font-bold">{@deployment_group.failure_rate_amount}</span> failures per <span class="font-bold">{@deployment_group.failure_rate_seconds}</span> seconds
              </span>
            </div>

            <div class="flex gap-4 items-center pb-6">
              <span class="text-sm text-nerves-gray-500">Failure threshold:</span>
              <span class="text-sm text-zinc-300">{@deployment_group.failure_threshold}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Device failure rate:</span>
              <span class="text-sm text-zinc-300">
                <span class="font-bold">{@deployment_group.device_failure_rate_amount}</span> failures per <span class="font-bold">{@deployment_group.device_failure_rate_seconds}</span> seconds
              </span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-40">Device failure threshold:</span>
              <span class="text-sm text-zinc-300">{@deployment_group.device_failure_threshold}</span>
            </div>
            <div class="flex gap-4 items-center pb-6">
              <span class="text-sm text-nerves-gray-500">Device penalty box timeout:</span>
              <span class="text-sm text-zinc-300">{@deployment_group.penalty_timeout_minutes}</span>
            </div>

            <div :if={!@deployment_group.connecting_code} class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Code sent on device connection:</span>
              <span class="text-sm text-zinc-300">No code configured</span>
            </div>
            <div :if={@deployment_group.connecting_code} class="flex gap-2 items-start">
              <span class="text-sm text-nerves-gray-500">Code sent on device connection:</span>
              <pre :if={!@deployment_group.connecting_code} class="text-sm text-zinc-300">
    {@deployment_group.connecting_code}
              </pre>
            </div>
          </div>

          <div class="flex flex-col gap-2 p-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
            <div class="h-9 flex items-start justify-between">
              <div class="text-neutral-50 font-medium leading-6">Device Matching Conditions</div>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-36">Tag selection:</span>
              <span :if={Enum.empty?(@deployment_group.conditions["tags"])} class="text-sm text-nerves-gray-500">No tags configured</span>
              <span :if={Enum.any?(@deployment_group.conditions["tags"])} class="flex gap-1">
                <span :for={tag <- @deployment_group.conditions["tags"]} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded">{tag}</span>
              </span>
            </div>
            <div class="flex gap-4 items-center pb-2">
              <span class="text-sm text-nerves-gray-500 w-36">Version requirement:</span>
              <code class="text-sm text-zinc-300">{@deployment_group.conditions["version"]}</code>
            </div>
            <div
              :if={@deployment_group.device_count > 0 || @unmatched_device_count > 0 || @matched_devices_outside_deployment_group_count > 0}
              class="flex flex-col justify-between pt-3 gap-2 border-t border-zinc-700"
            >
              <div :if={@deployment_group.device_count > 0 && @matched_device_count == @deployment_group.device_count} class="flex gap-4 pt-2 items-center">
                <span class="text-sm text-zinc-300">100% of devices in this deployment group match conditions</span>
              </div>
              <div :if={@matched_device_count != @deployment_group.device_count} class="flex gap-4 items-center">
                <span class="text-sm text-zinc-300">{round(@matched_device_count / @deployment_group.device_count * 100)}% of devices in this deployment group match conditions</span>
              </div>
              <div :if={@unmatched_device_count > 0} class="flex py-2 gap-2 items-center">
                <div class="text-sm text-zinc-300">
                  {@unmatched_device_count} {if @unmatched_device_count == 1, do: "device", else: "devices"}
                  <span class="text-sm text-nerves-gray-500">{if @unmatched_device_count == 1, do: "doesn't", else: "don't"} match inside deployment group</span>
                </div>
                <%!-- We have no way of filtering by version as of March 2025. When we do we can use this. --%>
                <%!-- <.link navigate={~p"/org/#{@org.name}/#{@product.name}/devices"} class="flex items-center h-6 bg-zinc-800 border border-zinc-700 rounded-full">
                  <.icon name="open" />
                </.link> --%>
                <button
                  class="flex items-center text-sm cursor-pointer pl-1 pr-2 h-6 bg-zinc-800 border border-zinc-700 rounded-full"
                  phx-click="remove-unmatched-devices-from-deployment-group"
                  data-confirm={"This will remove #{@unmatched_device_count} #{if @unmatched_device_count == 1, do: "device", else: "devices"} from #{@deployment_group.name}. Continue?"}
                >
                  <.icon name="trash" class="mr-1" /> Remove {if @unmatched_device_count == 1, do: "device", else: "devices"}
                </button>
                <div id="remove-devices-from-deployment-group" class="relative z-20" phx-hook="ToolTip" data-placement="top">
                  <.icon name="info" />
                  <div class="tooltip-content hidden w-max absolute top-0 left-0 z-20 text-xs px-2 py-1.5 rounded border border-[#3F3F46] bg-base-900 flex">
                    This action will remove {@unmatched_device_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"} from {@deployment_group.name}
                    <div class="tooltip-arrow absolute w-2 h-2 border-[#3F3F46] bg-base-900 origin-center rotate-45"></div>
                  </div>
                </div>
              </div>
              <div :if={@matched_devices_outside_deployment_group_count > 0} class="flex gap-2 items-center">
                <div class="text-sm text-zinc-300">
                  {@matched_devices_outside_deployment_group_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}
                  <span class="text-sm text-nerves-gray-500">{if @matched_devices_outside_deployment_group_count == 1, do: "matches", else: "match"} outside of deployment group</span>
                </div>
                <%!-- We have no way of filtering by version as of March 2025. When we do we can use this. --%>
                <%!-- <.link navigate={~p"/org/#{@org.name}/#{@product.name}/devices"} class="flex items-center h-6 bg-zinc-800 border border-zinc-700 rounded-full">
                  <.icon name="open" />
                </.link> --%>
                <button
                  class="flex items-center text-sm cursor-pointer pl-1 pr-2 h-6 bg-zinc-800 border border-zinc-700 rounded-full"
                  phx-click="move-matched-devices-to-deployment-group"
                  data-confirm={"This will move #{@matched_devices_outside_deployment_group_count} #{if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"} into #{@deployment_group.name}. Continue?"}
                >
                  <.icon name="folder-move" class="mr-1" /> Move {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}
                </button>
                <div id="move-devices-to-deployment-group" class="relative z-20" phx-hook="ToolTip" data-placement="top">
                  <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path
                      d="M10 12.5V10M10 7.5V7.49167M17.5 10C17.5 14.1421 14.1421 17.5 10 17.5C5.85786 17.5 2.5 14.1421 2.5 10C2.5 5.85786 5.85786 2.5 10 2.5C14.1421 2.5 17.5 5.85786 17.5 10Z"
                      stroke="#A1A1AA"
                      stroke-width="1.2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <div class="tooltip-content hidden w-max absolute top-0 left-0 z-20 text-xs px-2 py-1.5 rounded border border-[#3F3F46] bg-base-900 flex">
                    This action will move {@matched_devices_outside_deployment_group_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}<br />
                    that do not belong to a deployment <br />group into {@deployment_group.name}
                    <div class="tooltip-arrow absolute w-2 h-2 border-[#3F3F46] bg-base-900 origin-center rotate-45"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp deployment_group_percentage(_up_to_date_count, %{device_count: 0}), do: 0.0

  defp deployment_group_percentage(up_to_date_count, deployment_group) do
    floor(up_to_date_count / deployment_group.device_count * 100)
  end
end
