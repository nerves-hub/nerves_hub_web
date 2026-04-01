defmodule NervesHubWeb.Components.DeploymentGroupPage.Summary do
  use NervesHubWeb, :live_component

  import NervesHubWeb.LayoutView,
    only: [humanize_size: 1]

  alias NervesHub.Devices
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias Phoenix.Naming

  @impl Phoenix.LiveComponent
  def update(%{event: :update_matched_devices_count}, socket) do
    socket
    |> assign_matched_devices_count()
    |> ok()
  end

  def update(%{event: :update_inflight_info}, socket) do
    %{deployment_group: deployment_group} = socket.assigns

    inflight_updates = Devices.inflight_updates_for(deployment_group)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, Devices.updating_count(deployment_group))
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(deployment_group.current_release.firmware))
    |> ok()
  end

  def update(%{event: :stat_logged}, socket) do
    socket
    |> assign_update_stats(socket.assigns.deployment_group)
    |> ok()
  end

  def update(%{event: :firmware_deltas_updated}, socket) do
    socket
    |> assign(
      :deltas,
      Firmwares.get_deltas_by_target_firmware(socket.assigns.deployment_group.current_release.firmware)
    )
    |> ok()
  end

  def update(%{updated_deployment: deployment_group}, socket) do
    socket
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(deployment_group.current_release.firmware))
    |> assign_update_stats(deployment_group)
    |> assign_deltas_and_stats()
    |> assign_matched_devices_count()
    |> ok()
  end

  def update(assigns, socket) do
    %{deployment_group: deployment_group} = assigns

    inflight_updates = Devices.inflight_updates_for(deployment_group)
    updating_count = Devices.updating_count(deployment_group)

    socket
    |> assign(assigns)
    |> assign(
      :deltas,
      Firmwares.get_deltas_by_target_firmware(deployment_group.current_release.firmware)
    )
    |> assign_update_stats(deployment_group)
    |> assign_deltas_and_stats()
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, updating_count)
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:firmware, deployment_group.current_release.firmware)
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(deployment_group.current_release.firmware))
    |> assign(:update_stats, UpdateStats.stats_by_deployment(deployment_group))
    |> assign_matched_devices_count()
    |> ok()
  end

  defp assign_matched_devices_count(%{assigns: %{deployment_group: deployment_group}} = socket) do
    current_device_count = ManagedDeployments.get_device_count(deployment_group)

    matched_devices_count =
      ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true)

    matched_devices_outside_deployment_group_count =
      ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false)

    socket
    |> assign(:matched_device_count, matched_devices_count)
    |> assign(:unmatched_device_count, current_device_count - matched_devices_count)
    |> assign(
      :matched_devices_outside_deployment_group_count,
      matched_devices_outside_deployment_group_count
    )
    |> assign(:deployment_group, %{deployment_group | device_count: current_device_count})
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_version_for_stat", %{"version" => version}, socket) do
    update_stat_for_current_firmware =
      Enum.find(socket.assigns.update_stats, fn {_uuid, stats} -> stats.version == version end)

    {:noreply, assign(socket, :update_stat_for_current_firmware, update_stat_for_current_firmware)}
  end

  def handle_event("delete_delta", %{"id" => id}, socket) do
    delta_to_delete = Enum.find(socket.assigns.deltas, &(&1.id == String.to_integer(id)))

    {:ok, _} = Firmwares.delete_firmware_delta(delta_to_delete)

    deltas = Enum.filter(socket.assigns.deltas, &(&1.id != delta_to_delete.id))

    socket =
      socket
      |> assign(:deltas, deltas)
      |> put_flash(:info, "Delta successfully deleted")

    {:noreply, socket}
  end

  def handle_event("retry_delta", %{"id" => id}, socket) do
    delta = Enum.find(socket.assigns.deltas, &(&1.id == String.to_integer(id)))

    {:ok, _} = Firmwares.delete_firmware_delta(delta)
    {:ok, _} = Firmwares.attempt_firmware_delta(delta.source_id, delta.target_id)

    socket = put_flash(socket, :info, "Retrying delta generation")
    {:noreply, socket}
  end

  def handle_event("generate-firmware-deltas", _params, %{assigns: %{deployment_group: deployment_group}} = socket) do
    {:ok, _} = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)

    socket
    |> put_flash(:info, "Generating firmware deltas")
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex h-full flex-col items-start gap-4 p-6">
      <div :if={@waiting_for_update_count == 0} class="bg-base-900 border-base-700 w-full items-center justify-center rounded border p-4">
        <div class="flex h-10 items-center justify-center text-xl/6 font-medium text-neutral-50">All devices are up to date!</div>
      </div>

      <div :if={@waiting_for_update_count > 0} class="bg-base-900 border-base-700 box-content flex h-24 w-full items-center justify-center rounded border">
        <div class="relative top-0 z-20 w-full items-center justify-center overflow-visible rounded">
          <div
            :if={@deployment_group.is_active}
            class="border-success-500 absolute -top-px z-40 rounded-tl border-t"
            role="progressbar"
            style={"width: #{deployment_group_percentage(@up_to_date_count, @deployment_group)}%"}
          >
            <div class="bg-progress-glow h-16 w-full animate-pulse" />
          </div>

          <div class="bg-surface-muted/20 my-1 flex flex-col items-center justify-center gap-1 p-2 text-sm font-medium">
            <div class="text-base">{deployment_group_percentage(@up_to_date_count, @deployment_group)}% of devices updated</div>
            <div>{@updating_count} device(s) updating - {@waiting_for_update_count} device(s) waiting</div>
          </div>
        </div>
      </div>

      <div class="flex size-full gap-4">
        <div class="flex w-1/2 flex-col gap-4">
          <div class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border p-4">
            <div class="flex h-9 items-start justify-between">
              <div class="leading-6 font-medium text-neutral-50">Current Release</div>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 w-16 text-sm">Firmware:</span>

              <.link
                navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/firmware/#{@deployment_group.current_release.firmware}"}
                class="bg-base-800 border-base-700 flex items-center gap-1 rounded-full border py-0.5 pr-2.5 pl-1.5"
              >
                <span class="text-base-300 text-xs tracking-tight">
                  {@deployment_group.current_release.firmware.version} ({String.slice(@deployment_group.current_release.firmware.uuid, 0..7)})
                </span>
              </.link>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 w-16 text-sm">Size:</span>
              <span class="text-nerves-gray-700 pl-1 text-xs">{humanize_size(@deployment_group.current_release.firmware.size)}</span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 w-16 text-sm">Archive:</span>

              <.link
                :if={@deployment_group.current_release.archive}
                navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/archives/#{@deployment_group.current_release.archive}"}
                class="bg-base-800 border-base-700 flex items-center gap-1 rounded-full border py-0.5 pr-2.5 pl-1.5"
              >
                <span class="text-base-300 text-xs tracking-tight">
                  {@deployment_group.current_release.archive.version} ({String.slice(@deployment_group.current_release.archive.uuid, 0..7)})
                </span>
              </.link>
              <span :if={is_nil(@deployment_group.current_release.archive)} class="text-nerves-gray-500 pl-1 text-xs">No archive configured</span>
            </div>
          </div>

          <div :if={@deployment_group.delta_updatable or Enum.any?(@deltas)} class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border">
            <div class="flex h-9 items-start justify-between p-4">
              <div class="leading-6 font-medium text-neutral-50">Firmware deltas</div>
            </div>
            <div class="flex flex-col gap-3 p-4">
              <div class="flex items-center gap-4">
                <span class="text-nerves-gray-500 text-sm">Firmware deltas provide smaller update payloads by only sending the differences between firmware versions.</span>
              </div>
            </div>
            <div :if={Enum.any?(@deltas)} class="bg-base-900 border-base-700 rounded-b border-t">
              <div class="flex flex-col">
                <div class="listing">
                  <table>
                    <thead>
                      <tr>
                        <th class="rounded-tl">From</th>
                        <th>Status</th>
                        <th>Size</th>
                        <th>Saving</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={delta <- @deltas} class="border-base-800 relative border-b last:rounded-b last:border-0">
                        <td>
                          <div class="flex items-center gap-[8px]">
                            {delta.source.version}
                          </div>
                        </td>

                        <td>
                          <div data-status={delta.status} class="data-[status=failed]:text-alert data-[status=processing]:text-warning data-[status=timed_out]:text-alert flex items-center gap-[8px]">
                            {if delta.status == :completed do
                              "Ready"
                            else
                              Naming.humanize(delta.status)
                            end}
                          </div>
                        </td>

                        <td>
                          <div class="flex items-center gap-[8px]">
                            {if delta.status == :completed do
                              Sizeable.filesize(delta.size)
                            else
                              "-"
                            end}
                          </div>
                        </td>

                        <td>
                          <div class="flex items-center gap-[8px]">
                            {if delta.status == :completed do
                              Sizeable.filesize(delta.target_size - delta.size)
                            else
                              "-"
                            end}
                          </div>
                        </td>

                        <td>
                          <div class="relative flex items-center gap-[8px]">
                            <a
                              :if={delta.status in [:failed, :timed_out, :completed]}
                              class="text-base-300 cursor-pointer underline"
                              phx-click="delete_delta"
                              data-confirm="Are you sure you want to delete this firmware delta? Warning: If other deployments are also using this delta, this will affect them as well."
                              phx-target={@myself}
                              phx-value-id={delta.id}
                            >
                              Delete
                            </a>
                            <a
                              :if={delta.status in [:failed, :timed_out]}
                              class="text-base-300 cursor-pointer underline"
                              phx-click="retry_delta"
                              data-confirm="Are you sure you want to retry firmware delta generation? Warning: If other deployments are also using this delta, this will affect them as well."
                              phx-target={@myself}
                              phx-value-id={delta.id}
                            >
                              Retry
                            </a>
                            <span :if={delta.status == :processing}>-</span>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
            <div :if={Enum.empty?(@deltas)} class="bg-base-900 border-base-700 flex justify-between gap-6 rounded-b border-t p-4">
              <div class="flex items-center">
                <span class="text-nerves-gray-500 text-sm">No firmware deltas are available.</span>
              </div>
              <.button
                type="button"
                aria-label="Generate firmware deltas"
                phx-target={@myself}
                phx-click="generate-firmware-deltas"
              >
                Generate firmware deltas
              </.button>
            </div>
          </div>

          <div class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border p-4">
            <div class="flex h-9 items-start justify-between">
              <div class="leading-6 font-medium text-neutral-50">Inflight updates</div>
            </div>
            <div class="flex flex-col gap-3">
              <div :if={@inflight_updates == []} class="flex items-center gap-4">
                <span class="text-nerves-gray-500 text-sm">No devices are currently updating.</span>
              </div>
              <div :if={@inflight_updates != []} class="flex items-center gap-4">
                <span class="text-nerves-gray-500 text-sm">
                  <span class="font-semibold">{Enum.count(@inflight_updates)}</span>
                  device(s) are currently updating.
                  <.link
                    class="text-base-300 underline"
                    navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices?#{[only_updating: true, sort: "connection_established_at", sort_direction: "desc"]}"}
                  >
                    View details
                  </.link>
                </span>
              </div>
              <div :for={inflight_update <- @inflight_updates} :if={@inflight_updates != []} class="flex items-center gap-4">
                <span class="bg-base-800 text-base-300 flex h-7 items-center rounded px-2 py-1">
                  <.link navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices/#{inflight_update.device}"}>
                    {inflight_update.device.identifier}
                  </.link>
                </span>
              </div>
            </div>
          </div>
        </div>
        <div class="flex w-1/2 flex-col gap-4">
          <div class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border p-4">
            <div class="flex h-9 items-start justify-between">
              <div class="leading-6 font-medium text-neutral-50">Settings Overview</div>
            </div>

            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Concurrent device updates:</span>
              <span class="text-base-300 text-sm">{@deployment_group.concurrent_updates}</span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Minutes before expiring updates:</span>
              <span class="text-base-300 text-sm">{@deployment_group.inflight_update_expiration_minutes}</span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Device failure rate:</span>
              <span class="text-base-300 text-sm">
                <span class="font-bold">{@deployment_group.device_failure_rate_amount}</span> failures per <span class="font-bold">{@deployment_group.device_failure_rate_seconds}</span> seconds
              </span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 w-40 text-sm">Device failure threshold:</span>
              <span class="text-base-300 text-sm">{@deployment_group.device_failure_threshold}</span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Device penalty box timeout:</span>
              <span class="text-base-300 text-sm">{@deployment_group.penalty_timeout_minutes}</span>
            </div>

            <div class="flex items-center gap-4 pb-6">
              <span class="text-nerves-gray-500 text-sm">Queue management:</span>
              <span class="text-base-300 text-sm">{@deployment_group.queue_management}</span>
            </div>

            <div :if={@deployment_group.priority_queue_enabled} class="border-base-700 flex items-center gap-4 border-t pt-4">
              <span class="text-nerves-gray-500 text-sm">Priority queue enabled:</span>
              <span class="text-success text-sm">Yes</span>
            </div>
            <div :if={@deployment_group.priority_queue_enabled} class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Priority queue concurrent:</span>
              <span class="text-base-300 text-sm">{@deployment_group.priority_queue_concurrent_updates}</span>
            </div>
            <div :if={@deployment_group.priority_queue_enabled} class="flex items-center gap-4 pb-6">
              <span class="text-nerves-gray-500 text-sm">Priority version threshold:</span>
              <span class="text-base-300 text-sm">{@deployment_group.priority_queue_firmware_version_threshold || "Not set"}</span>
            </div>

            <div :if={!@deployment_group.connecting_code} class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">Code sent on device connection:</span>
              <span class="text-base-300 text-sm">No code configured</span>
            </div>
            <div :if={@deployment_group.connecting_code} class="flex items-start gap-2">
              <span class="text-nerves-gray-500 text-sm">Code sent on device connection:</span>
              <pre :if={!@deployment_group.connecting_code} class="text-base-300 text-sm">
    {@deployment_group.connecting_code}
              </pre>
            </div>
          </div>

          <div class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border p-4">
            <div class="flex h-9 items-start justify-between">
              <div class="leading-6 font-medium text-neutral-50">Device Matching Conditions</div>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-nerves-gray-500 w-36 text-sm">Tag selection:</span>
              <span :if={Enum.empty?(@deployment_group.conditions.tags || [])} class="text-nerves-gray-500 text-sm">No tags configured</span>
              <span :if={Enum.any?(@deployment_group.conditions.tags || [])} class="flex gap-1">
                <span :for={tag <- @deployment_group.conditions.tags} class="bg-base-800 border-base-800 text-base-300 rounded border px-2 py-1 text-sm">{tag}</span>
              </span>
            </div>
            <div class="flex items-center gap-4 pb-2">
              <span class="text-nerves-gray-500 w-36 text-sm">Version requirement:</span>
              <code class="text-base-300 text-sm">{@deployment_group.conditions.version}</code>
            </div>
            <div
              :if={@deployment_group.device_count > 0 || @unmatched_device_count > 0 || @matched_devices_outside_deployment_group_count > 0}
              class="border-base-700 flex flex-col justify-between gap-2 border-t pt-3"
            >
              <div :if={@deployment_group.device_count > 0 && @matched_device_count == @deployment_group.device_count} class="flex items-center gap-4 pt-2">
                <span class="text-base-300 text-sm">100% of devices in this deployment group match conditions</span>
              </div>
              <div :if={@matched_device_count != @deployment_group.device_count} class="flex items-center gap-4">
                <span class="text-base-300 text-sm">{round(@matched_device_count / @deployment_group.device_count * 100)}% of devices in this deployment group match conditions</span>
              </div>
              <div :if={@unmatched_device_count > 0} class="flex items-center gap-2 py-2">
                <div class="text-base-300 text-sm">
                  {@unmatched_device_count} {if @unmatched_device_count == 1, do: "device", else: "devices"}
                  <span class="text-nerves-gray-500 text-sm">{if @unmatched_device_count == 1, do: "doesn't", else: "don't"} match inside deployment group</span>
                </div>
                <%!-- We have no way of filtering by version as of March 2025. When we do we can use this. --%>
                <%!-- <.link navigate={~p"/org/#{@org}/#{@product}/devices"} class="flex items-center h-6 bg-base-800 border border-base-700 rounded-full">
                  <.icon name="open" class="stroke-base-400" />
                </.link> --%>
                <button
                  class="bg-base-800 border-base-700 flex h-6 cursor-pointer items-center rounded-full border pr-2 pl-1 text-sm"
                  phx-click="remove-unmatched-devices-from-deployment-group"
                  data-confirm={"This will remove #{@unmatched_device_count} #{if @unmatched_device_count == 1, do: "device", else: "devices"} from #{@deployment_group.name}. Continue?"}
                >
                  <.icon name="trash" class="stroke-base-400 mr-1" /> Remove {if @unmatched_device_count == 1, do: "device", else: "devices"}
                </button>
                <div id="remove-devices-from-deployment-group" class="relative z-20" phx-hook="ToolTip" data-placement="top">
                  <.icon name="info" class="stroke-base-400" />
                  <div class="bg-surface-muted border-base-700 tooltip-content absolute top-0 left-0 z-20 hidden w-max rounded border px-2 py-1.5 text-xs">
                    This action will remove {@unmatched_device_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"} from {@deployment_group.name}
                    <div class="bg-surface-muted border-base-700 tooltip-arrow absolute size-2 origin-center rotate-45"></div>
                  </div>
                </div>
              </div>
              <div :if={@matched_devices_outside_deployment_group_count > 0} class="flex items-center gap-2">
                <div class="text-base-300 text-sm">
                  {@matched_devices_outside_deployment_group_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}
                  <span class="text-nerves-gray-500 text-sm">{if @matched_devices_outside_deployment_group_count == 1, do: "matches", else: "match"} outside of deployment group</span>
                </div>
                <%!-- We have no way of filtering by version as of March 2025. When we do we can use this. --%>
                <%!-- <.link navigate={~p"/org/#{@org}/#{@product}/devices"} class="flex items-center h-6 bg-base-800 border border-base-700 rounded-full">
                  <.icon name="open" class="stroke-base-400" />
                </.link> --%>
                <button
                  class="bg-base-800 border-base-700 flex h-6 cursor-pointer items-center rounded-full border pr-2 pl-1 text-sm"
                  phx-click="move-matched-devices-to-deployment-group"
                  data-confirm={"This will move #{@matched_devices_outside_deployment_group_count} #{if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"} into #{@deployment_group.name}. Continue?"}
                >
                  <.icon name="folder-move" class="stroke-base-400 mr-1" /> Move {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}
                </button>
                <div id="move-devices-to-deployment-group" class="relative z-20" phx-hook="ToolTip" data-placement="top">
                  <svg class="size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path
                      d="M10 12.5V10M10 7.5V7.49167M17.5 10C17.5 14.1421 14.1421 17.5 10 17.5C5.85786 17.5 2.5 14.1421 2.5 10C2.5 5.85786 5.85786 2.5 10 2.5C14.1421 2.5 17.5 5.85786 17.5 10Z"
                      stroke="#A1A1AA"
                      stroke-width="1.2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <div class="bg-surface-muted border-base-700 tooltip-content absolute top-0 left-0 z-20 hidden w-max rounded border px-2 py-1.5 text-xs">
                    This action will move {@matched_devices_outside_deployment_group_count} {if @matched_devices_outside_deployment_group_count == 1, do: "device", else: "devices"}<br />
                    that do not belong to a deployment <br />group into {@deployment_group.name}
                    <div class="bg-surface-muted border-base-700 tooltip-arrow absolute size-2 origin-center rotate-45"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-base-900 border-base-700 shadow-device-details-content flex flex-col gap-2 rounded border p-4">
            <div class="flex items-start justify-between">
              <div class="leading-6 font-medium text-neutral-50">Transfer Stats</div>
            </div>
            <div :if={is_nil(@update_stat_for_current_firmware)} class="flex items-center gap-4">
              <span class="text-nerves-gray-500 text-sm">No stats recorded for firmware {@deployment_group.current_release.firmware.version}</span>
            </div>
            <div :if={@update_stat_for_current_firmware} class="flex flex-col gap-2">
              <%= with {_uuid, stats} <- @update_stat_for_current_firmware do %>
                <div class="flex w-1/4 flex-col gap-6">
                  <form phx-change="select_version_for_stat" phx-target={@myself}>
                    <.input
                      label="Version"
                      hide_label={true}
                      id="version"
                      name="version"
                      type="select"
                      options={Enum.map(@update_stats, fn {_uuid, stats} -> {stats.version, stats.version} end)}
                      value={stats.version}
                    />
                  </form>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-nerves-gray-500 text-sm">Update count:</span>
                  <span class="text-base-300 text-sm">{stats.total_updates}</span>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-nerves-gray-500 text-sm">Total updates size:</span>
                  <span class="text-base-300 text-sm">{Sizeable.filesize(stats.total_update_bytes)}</span>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-nerves-gray-500 text-sm">Delta update savings:</span>
                  <span class="text-base-300 text-sm">{Sizeable.filesize(stats.total_saved_bytes)}</span>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-nerves-gray-500 text-sm">Average size per device:</span>
                  <span class="text-base-300 text-sm">{Sizeable.filesize(stats.total_update_bytes / stats.total_updates)}</span>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-nerves-gray-500 text-sm">Average saved per device:</span>
                  <span class="text-base-300 text-sm">{Sizeable.filesize(stats.total_saved_bytes / stats.total_updates)}</span>
                </div>
              <% end %>
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

  defp assign_update_stats(socket, deployment_group) do
    update_stats = UpdateStats.stats_by_deployment(deployment_group)

    update_stat_for_current_firmware =
      Enum.find(update_stats, fn {uuid, _stats} -> uuid == deployment_group.current_release.firmware.uuid end)

    socket
    |> assign(:update_stats, update_stats)
    |> assign(:update_stat_for_current_firmware, update_stat_for_current_firmware)
  end

  defp assign_deltas_and_stats(%{assigns: %{deployment_group: deployment_group}} = socket) do
    :ok = Firmwares.subscribe_firmware_delta_target(deployment_group.current_release.firmware.id)

    socket
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(deployment_group.current_release.firmware))
  end
end
