defmodule NervesHubWeb.Components.DevicePage.FirmwareHistoryTab do
  use NervesHubWeb, tab_component: :firmware_history

  alias NervesHub.Devices.DeviceFirmwares
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.Pager

  def tab_params(params, _uri, socket) do
    page_number = String.to_integer(Map.get(params, "page_number", "1"))
    page_size = String.to_integer(Map.get(params, "page_size", "25"))
    view = if params["view"] == "attempts", do: :attempts, else: :installed

    socket
    |> assign(:history_view, view)
    |> history_assigns(page_number, page_size)
    |> cont()
  end

  def cleanup() do
    [:history_view, :device_firmwares, :update_attempts, :device_firmwares_pager]
  end

  defp history_assigns(%{assigns: %{history_view: :attempts}} = socket, page_number, page_size) do
    {attempts, pager} = UpdateHistory.device_attempts(socket.assigns.device, page_number, page_size)

    socket
    |> assign(:update_attempts, attempts)
    |> assign(:device_firmwares, [])
    |> assign(:device_firmwares_pager, pager)
  end

  defp history_assigns(socket, page_number, page_size) do
    {history, pager} =
      DeviceFirmwares.paginate(socket.assigns.device, %{
        page: page_number,
        page_size: page_size
      })

    socket
    |> assign(:device_firmwares, history)
    |> assign(:update_attempts, [])
    |> assign(:device_firmwares_pager, Map.from_struct(pager))
  end

  def render(assigns) do
    ~H"""
    <div
      id="device-firmwares-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex h-full flex-col items-start gap-4 opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <div class="w-full p-4 sm:p-6">
        <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
          <div class="flex min-h-12 shrink-0 flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2">
            <%!-- Across the card on a phone, a thumb's height. --%>
            <nav aria-label="Firmware history" class="flex h-7 overflow-clip rounded border border-line-control max-sm:h-10 max-sm:w-full">
              <.link
                :for={{view, label} <- [installed: "Installed firmware", attempts: "Update attempts"]}
                patch={view_path(@org, @product, @device, view)}
                aria-current={if @history_view == view, do: "page"}
                class="flex items-center border-l border-line-control px-2.5 text-xs font-medium text-content-muted first:border-l-0 hover:text-content-strong aria-[current=page]:bg-surface-muted aria-[current=page]:text-content-strong max-sm:flex-1 max-sm:justify-center max-sm:text-sm"
              >
                {label}
              </.link>
            </nav>
            <span class="text-xs text-content-faint max-sm:basis-full">
              {if @history_view == :attempts, do: "How each update sent to this device ended", else: "Each firmware the device reported, newest first"}
            </span>
            <span
              :if={@history_view == :attempts}
              class={["ml-auto text-xs max-sm:ml-0 max-sm:basis-full", if(@device.consecutive_failed_updates > 0, do: "text-warning-content", else: "text-content-faint")]}
            >
              {failures_in_a_row(@device.consecutive_failed_updates)}
            </span>
          </div>

          <.installed_table
            :if={@history_view == :installed}
            device={@device}
            entries={@device_firmwares}
            first_page?={@device_firmwares_pager.current_page == 1}
            org={@org}
            product={@product}
            time_zone={@time_zone}
          />
          <.attempts_table :if={@history_view == :attempts} attempts={@update_attempts} org={@org} product={@product} time_zone={@time_zone} />

          <Pager.footer id="firmware-history-pager" pager={@device_firmwares_pager} />
        </div>
      </div>
    </div>
    """
  end

  attr(:device, :any, required: true)
  attr(:entries, :list, required: true)
  attr(:first_page?, :boolean, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp installed_table(assigns) do
    ~H"""
    <div :if={@entries == []} class="flex items-center justify-center border-t border-line-subtle p-14">
      <span class="text-ui text-content-faint">No firmware history found for the device.</span>
    </div>
    <%!-- On a phone each row is a card of two or three lines: the version
          and its validation, then when it was reported. --%>
    <div :if={@entries != []} class="overflow-x-auto px-4">
      <table class="w-full text-left max-sm:block sm:min-w-xl">
        <thead class="border-t border-line-subtle max-sm:hidden">
          <tr class="text-label text-content-faint uppercase">
            <th class="h-8.5 pt-1.5 font-medium">Version</th>
            <th class="h-8.5 w-46 pt-1.5 font-medium">Validation</th>
            <th class="h-8.5 w-70 pt-1.5 font-medium">Reported</th>
          </tr>
        </thead>
        <tbody class="max-sm:block">
          <tr
            :for={{entry, index} <- Enum.with_index(@entries)}
            id={"device-firmware-#{entry.id}"}
            class="h-12 border-t border-line-subtle max-sm:grid max-sm:h-auto max-sm:grid-cols-[minmax(0,1fr)_auto] max-sm:items-start max-sm:gap-x-3 max-sm:gap-y-1.5 max-sm:py-3"
          >
            <td class="max-sm:min-w-0">
              <span class="flex items-center gap-2.5 max-sm:flex-wrap max-sm:gap-y-1">
                <span class="font-mono text-ui text-content-strong max-sm:text-sm max-sm:font-semibold">{entry.firmware_metadata.version}</span>
                <.firmware_uuid device_firmware={entry} org={@org} product={@product} />
                <span :if={@first_page? and index == 0 and running?(@device, entry)} class="flex items-center gap-1.5 text-xs font-medium text-success-content max-sm:hidden">
                  <span class="size-1.5 rounded-full bg-success"></span>Running now
                </span>
              </span>
            </td>
            <td><.validation entry={entry} /></td>
            <td class="whitespace-nowrap max-sm:col-span-2 max-sm:whitespace-normal">
              <%!-- A phone puts Running now on this line, with when. --%>
              <span :if={@first_page? and index == 0 and running?(@device, entry)} class="mr-1 inline-flex items-center gap-1.5 text-ui font-medium text-success-content sm:hidden">
                <span class="size-1.5 rounded-full bg-success"></span>Running now<span class="font-normal text-content-faint">·</span>
              </span>
              <span class="text-ui text-content-strong">{RelativeTime.from_now(entry.inserted_at)}</span>
              <.local_datetime at={entry.inserted_at} time_zone={@time_zone} format={:short_datetime_seconds} zone_label={false} class="ml-1.5 text-xs whitespace-nowrap text-content-faint" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:attempts, :list, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp attempts_table(assigns) do
    ~H"""
    <div :if={@attempts == []} class="flex items-center justify-center border-t border-line-subtle p-14">
      <span class="text-ui text-content-faint">No update attempts recorded for the device.</span>
    </div>
    <%!-- On a phone each attempt is a card: the update and how it ended, why,
          then when and who sent it. --%>
    <div :if={@attempts != []} class="overflow-x-auto px-4">
      <table class="w-full text-left max-sm:block sm:min-w-2xl">
        <thead class="border-t border-line-subtle max-sm:hidden">
          <tr class="text-label text-content-faint uppercase">
            <th class="h-8.5 w-41 pt-1.5 font-medium">When</th>
            <th class="h-8.5 w-49 pt-1.5 font-medium">Update</th>
            <th class="h-8.5 w-36 pt-1.5 font-medium">Outcome</th>
            <th class="h-8.5 pt-1.5 font-medium">Detail</th>
            <th class="h-8.5 w-38 pt-1.5 font-medium">Sent by</th>
          </tr>
        </thead>
        <tbody class="max-sm:block">
          <tr
            :for={attempt <- @attempts}
            data-update-attempt
            class="h-12 border-t border-line-subtle text-ui max-sm:grid max-sm:h-auto max-sm:grid-cols-[minmax(0,1fr)_auto] max-sm:items-center max-sm:gap-x-3 max-sm:gap-y-1.5 max-sm:py-3"
          >
            <td class="whitespace-nowrap max-sm:order-4">
              <.local_datetime at={attempt.timestamp} time_zone={@time_zone} format={:short_date} zone_label={false} class="font-medium text-content-strong" />
              <.local_datetime at={attempt.timestamp} time_zone={@time_zone} format={:time_seconds} zone_label={false} class="ml-1.5 text-xs text-content-faint" />
            </td>
            <td class="font-mono whitespace-nowrap max-sm:order-1 max-sm:text-sm">
              <.firmware_version firmware={attempt.source} org={@org} product={@product} class="text-content-muted" />
              <span class="mx-1 lucide-arrow-right size-3 align-[-1px] text-content-faint" aria-label="to"></span>
              <.firmware_version firmware={attempt.target} org={@org} product={@product} class="text-content-strong" />
            </td>
            <td class="max-sm:order-2"><.outcome status={attempt.status} /></td>
            <td class={["pr-4 text-content-body max-sm:order-3 max-sm:col-span-2 max-sm:pr-0", !attempt.reason && attempt.status == :succeeded && "max-sm:hidden"]}>
              {attempt.reason || detail(attempt.status)}
            </td>
            <td class="whitespace-nowrap max-sm:order-5 max-sm:min-w-0 max-sm:justify-self-end max-sm:truncate">
              <.link
                :if={attempt.deployment_group}
                navigate={~p"/org/#{@org}/#{@product}/deployment_groups/#{attempt.deployment_group.name}"}
                class="text-content-strong underline decoration-line-strong underline-offset-4 hover:decoration-content-muted"
              >
                {attempt.deployment_group.name}
              </.link>
              <span :if={!attempt.deployment_group} class="text-content-muted">Manual request</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:entry, :any, required: true)

  defp validation(assigns) do
    ~H"""
    <span class={["rounded px-1.5 py-0.5 text-xs font-medium whitespace-nowrap", validation_tone(@entry)]}>
      {validation_label(@entry)}
    </span>
    """
  end

  defp validation_label(%{firmware_auto_revert_detected: true}), do: "Revert detected"
  defp validation_label(%{firmware_validation_status: :validated}), do: "Validated"
  defp validation_label(%{firmware_validation_status: :not_validated}), do: "Not validated"
  defp validation_label(_), do: "Unknown"

  defp validation_tone(%{firmware_auto_revert_detected: true}), do: "bg-alert-soft text-alert-content"
  defp validation_tone(%{firmware_validation_status: :validated}), do: "bg-success-soft text-success-content"
  defp validation_tone(%{firmware_validation_status: :not_validated}), do: "bg-alert-soft text-alert-content"
  defp validation_tone(_), do: "border border-line-default text-content-body"

  attr(:status, :atom, required: true)

  defp outcome(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5 rounded px-1.5 py-0.5 text-xs font-medium whitespace-nowrap", outcome_tone(@status)]}>
      <span class="size-1.5 rounded-full bg-current"></span>{outcome_label(@status)}
    </span>
    """
  end

  defp outcome_label(status), do: status |> Atom.to_string() |> String.capitalize()

  defp outcome_tone(:succeeded), do: "bg-success-soft text-success-content"
  defp outcome_tone(:rescheduled), do: "border border-line-default text-content-body"
  defp outcome_tone(_failure), do: "bg-alert-soft text-alert-content"

  defp detail(:succeeded), do: "—"
  defp detail(:failed), do: "The device reported an error while updating"
  defp detail(:ignored), do: "The device declined the update"
  defp detail(:rescheduled), do: "The device asked for the update later"
  defp detail(:expired), do: "The update stopped making progress"
  defp detail(:abandoned), do: "The device came back still running its old firmware"

  attr(:firmware, :map, default: nil)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:class, :string, required: true)

  defp firmware_version(%{firmware: %{available?: true}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/org/#{@org}/#{@product}/firmware/#{@firmware.uuid}"}
      class={[@class, "underline decoration-line-strong underline-offset-4 hover:decoration-content-muted"]}
    >
      {version(@firmware)}
    </.link>
    """
  end

  defp firmware_version(assigns) do
    ~H"""
    <span class={@class} title={@firmware && @firmware.uuid}>{version(@firmware)}</span>
    """
  end

  defp version(nil), do: "—"
  defp version(%{version: nil, uuid: uuid}), do: String.slice(uuid, 0..7)
  defp version(%{version: version}), do: version

  defp failures_in_a_row(0), do: "No failures in a row"
  defp failures_in_a_row(1), do: "1 failure in a row"
  defp failures_in_a_row(count), do: "#{count} failures in a row"

  defp running?(%{firmware_metadata: %{uuid: uuid}}, %{firmware_metadata: %{uuid: uuid}}), do: true
  defp running?(_device, _entry), do: false

  defp view_path(org, product, device, :installed), do: ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history"

  defp view_path(org, product, device, :attempts),
    do: ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?view=attempts"

  attr(:device_firmware, :any, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)

  defp firmware_uuid(%{device_firmware: %{firmware_id: nil}} = assigns) do
    ~H"""
    <span class="font-mono text-xs text-content-muted">{String.slice(@device_firmware.firmware_metadata.uuid, 0..7)}</span>
    <span class="text-xs text-content-muted">Not uploaded to this product</span>
    """
  end

  defp firmware_uuid(assigns) do
    ~H"""
    <.link
      navigate={~p"/org/#{@org}/#{@product}/firmware/#{@device_firmware.firmware_metadata.uuid}"}
      class="font-mono text-xs text-content-muted underline decoration-line-strong underline-offset-4 hover:text-content-strong"
    >
      {String.slice(@device_firmware.firmware_metadata.uuid, 0..7)}
    </.link>
    """
  end

  def hooked_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = view_params(socket, %{"page_size" => page_size, "page_number" => "1"})

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?#{params}"

    socket
    |> history_assigns(1, String.to_integer(page_size))
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event("paginate", %{"page" => page_num}, socket) do
    params =
      view_params(socket, %{"page_size" => socket.assigns.device_firmwares_pager.page_size, "page_number" => page_num})

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?#{params}"

    socket
    |> history_assigns(
      String.to_integer(page_num),
      socket.assigns.device_firmwares_pager.page_size
    )
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event(_name, _params, socket), do: {:cont, socket}

  defp view_params(%{assigns: %{history_view: :attempts}}, params), do: Map.put(params, "view", "attempts")
  defp view_params(_socket, params), do: params

  def hooked_info(_name, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}
end
