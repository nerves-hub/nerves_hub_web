defmodule NervesHubWeb.Components.DeploymentPage.Summary do
  use NervesHubWeb, :live_component

  alias NervesHub.Devices

  def update(%{update_inflight_info: true}, socket) do
    deployment = socket.assigns.deployment

    inflight_updates = Devices.inflight_updates_for(deployment)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment))
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
      <div :if={@waiting_for_update_count == 0} class="w-full flex p-4 items-center justify-center rounded border border-zinc-700 bg-zinc-900">
        <div class="text-neutral-50 font-medium leading-6">All devices are up to date!</div>
      </div>

      <div :if={@waiting_for_update_count > 0} class="w-full box-content flex items-center justify-center rounded border border-zinc-700 bg-zinc-900">
        <div class="relative sticky top-0 w-full items-center justify-center rounded overflow-visible z-20">
          <div class="z-40 absolute -top-px border-t rounded-tl border-success-500" role="progressbar" style={"width: #{deployment_percentage(@up_to_date_count, @deployment)}%"}>
            <div class="animate-pulse bg-progress-glow w-full h-16" />
          </div>

          <div class="flex items-center justify-center mt-1 py-2 px-2 bg-base-900/20 text-sm font-medium">
            {deployment_percentage(@up_to_date_count, @deployment)}% of devices updated - {@waiting_for_update_count} device(s) waiting to be updated
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
                navigate={~p"/org/#{@org.name}/#{@product.name}/firmware/#{@deployment.firmware.uuid}"}
                class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
              >
                <span class="text-xs text-zinc-300 tracking-tight">{@deployment.firmware.version} ({String.slice(@deployment.firmware.uuid, 0..7)})</span>
              </.link>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-16">Archive:</span>

              <.link
                :if={@deployment.archive}
                navigate={~p"/org/#{@org.name}/#{@product.name}/archives/#{@deployment.archive.uuid}"}
                class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
              >
                <span class="text-xs text-zinc-300 tracking-tight">{@deployment.archive.version} ({String.slice(@deployment.archive.uuid, 0..7)})</span>
              </.link>
              <span class="pl-1 text-xs text-nerves-gray-500">No archive configured</span>
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
              <span class="text-sm text-zinc-300">{@deployment.concurrent_updates}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Minutes before expiring updates:</span>
              <span class="text-sm text-zinc-300">{@deployment.inflight_update_expiration_minutes}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Failure rate:</span>
              <span class="text-sm text-zinc-300">
                <span class="font-bold">{@deployment.failure_rate_amount}</span> failures per <span class="font-bold">{@deployment.failure_rate_seconds}</span> seconds
              </span>
            </div>

            <div class="flex gap-4 items-center pb-6">
              <span class="text-sm text-nerves-gray-500">Failure threshold:</span>
              <span class="text-sm text-zinc-300">{@deployment.failure_threshold}</span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Device failure rate:</span>
              <span class="text-sm text-zinc-300">
                <span class="font-bold">{@deployment.device_failure_rate_amount}</span> failures per <span class="font-bold">{@deployment.device_failure_rate_seconds}</span> seconds
              </span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-40">Device failure threshold:</span>
              <span class="text-sm text-zinc-300">{@deployment.device_failure_threshold}</span>
            </div>
            <div class="flex gap-4 items-center pb-6">
              <span class="text-sm text-nerves-gray-500">Device penalty box timeout:</span>
              <span class="text-sm text-zinc-300">{@deployment.penalty_timeout_minutes}</span>
            </div>

            <div :if={!@deployment.connecting_code} class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500">Code sent on device connection:</span>
              <span class="text-sm text-zinc-300">No code configured</span>
            </div>
            <div :if={@deployment.connecting_code} class="flex gap-2 items-start">
              <span class="text-sm text-nerves-gray-500">Code sent on device connection:</span>
              <pre :if={!@deployment.connecting_code} class="text-sm text-zinc-300">
    {@deployment.connecting_code}
              </pre>
            </div>
          </div>

          <div class="flex flex-col gap-2 p-4 rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
            <div class="h-9 flex items-start justify-between">
              <div class="text-neutral-50 font-medium leading-6">Device Matching Conditions</div>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-36">Tag selection:</span>
              <span :if={Enum.empty?(@deployment.conditions["tags"])} class="text-sm text-nerves-gray-500">No tags configured</span>
              <span :if={Enum.any?(@deployment.conditions["tags"])} class="flex gap-1">
                <span :for={tag <- @deployment.conditions["tags"]} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded">{tag}</span>
              </span>
            </div>
            <div class="flex gap-4 items-center">
              <span class="text-sm text-nerves-gray-500 w-36">Version requirement:</span>
              <code class="text-sm text-zinc-300">{@deployment.conditions["version"]}</code>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp deployment_percentage(up_to_date_count, deployment) do
    floor(up_to_date_count / deployment.device_count * 100)
  end
end
