defmodule NervesHubWeb.Components.DevicePage.ActivityTab do
  use NervesHubWeb, tab_component: :activity

  alias NervesHub.AuditLogs
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.Pager

  def tab_params(params, _uri, socket) do
    page_number = String.to_integer(Map.get(params, "page_number", "1"))
    page_size = String.to_integer(Map.get(params, "page_size", "25"))

    socket
    |> logs_and_pager_assigns(page_number, page_size)
    |> cont()
  end

  def cleanup() do
    [:activity, :audit_pager]
  end

  defp logs_and_pager_assigns(socket, page_number, page_size) do
    {logs, audit_pager} =
      AuditLogs.logs_for_feed(socket.assigns.device, %{
        page: page_number,
        page_size: page_size
      })

    audit_pager = Map.from_struct(audit_pager)

    socket
    |> assign(:activity, logs)
    |> assign(:audit_pager, audit_pager)
  end

  def render(assigns) do
    ~H"""
    <div
      id="activity-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex h-full flex-col items-start justify-between gap-4 opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <div class="w-full p-6">
        <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
          <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
            <div class="text-card-title text-content-strong">Latest activity</div>

            <.button type="link" square aria-label="Download activity" href={~p"/org/#{@org}/#{@product}/devices/#{@device}/audit_logs/download"}>
              <span class="lucide-download size-4" aria-hidden="true"></span>
            </.button>
          </div>
          <div :if={Enum.empty?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div class="flex items-center justify-center p-14">
              <span class="font-extralight text-content-faint">No audit logs found for the device.</span>
            </div>
          </div>
          <div :if={Enum.any?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div :for={entry <- @activity} class="flex h-16 items-center gap-6 p-2">
              <div class="flex h-8 items-center rounded-full border border-line-default bg-base-800 px-2 py-1">
                <span class={[kind_icon(entry.kind), "size-4 text-content-muted"]} aria-hidden="true"></span>
              </div>
              <div class="grow">
                <div class="text-content-body">{entry.description}</div>
                <div class="flex gap-2">
                  <div class="text-xs tracking-wide text-content-muted">
                    {RelativeTime.from_now(entry.inserted_at)}
                  </div>
                  <div class="flex items-center">
                    <svg class="size-0.5" viewBox="0 0 2 2" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <circle cx="1" cy="1" r="1" class="fill-base-500" />
                    </svg>
                  </div>
                  <div class="text-xs tracking-wide text-content-muted">
                    <.local_datetime at={entry.inserted_at} time_zone={@time_zone} format={:datetime_seconds} />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <Pager.render_with_page_sizes pager={@audit_pager} page_sizes={[25, 50, 100]} />
    </div>
    """
  end

  # One glyph per kind of entry (`NervesHub.AuditLogs.AuditLog.kinds/0`), as
  # the Activity tab boards in Paper draw them. Whole class names, so Tailwind
  # finds them. Entries written before kinds existed have none and get the
  # neutral glyph.
  @icons %{
    archive_sent: "lucide-archive",
    deployment_group_mismatch: "lucide-unlink",
    deployment_group_set: "lucide-rocket",
    deployment_update_sent: "lucide-download",
    device_moved: "lucide-arrow-right-left",
    device_rebooted: "lucide-power",
    device_updated: "lucide-pencil",
    firmware_metadata_updated: "lucide-file-text",
    firmware_pushed: "lucide-download",
    firmware_updated: "lucide-refresh-cw",
    firmware_validated: "lucide-shield-check",
    identify_requested: "lucide-locate",
    managed_updates_changed: "lucide-cpu",
    penalty_box_cleared: "lucide-lock-open",
    reconnect_requested: "lucide-wifi",
    script_run: "lucide-file-code-corner",
    shared_secret_created: "lucide-key-round",
    shared_secret_deactivated: "lucide-key-round",
    tags_changed: "lucide-tag",
    update_attempted: "lucide-hard-drive-download",
    update_failed: "lucide-triangle-exclamation-point",
    update_ignored: "lucide-circle-slash",
    update_mode_changed: "lucide-sliders-horizontal",
    update_requested: "lucide-download",
    update_rescheduled: "lucide-calendar-clock",
    updates_blocked: "lucide-ban",
    updates_disabled: "lucide-toggle-left",
    updates_enabled: "lucide-toggle-right"
  }

  @doc false
  # The glyph class for an entry's kind; public so the tests can check every
  # kind has one.
  @spec kind_icon(atom() | nil) :: String.t()
  def kind_icon(kind), do: Map.get(@icons, kind, "lucide-activity")

  def hooked_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => "1"}

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/activity?#{params}"

    socket
    |> logs_and_pager_assigns(1, String.to_integer(page_size))
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_size" => socket.assigns.audit_pager.page_size, "page_number" => page_num}

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/activity?#{params}"

    socket
    |> logs_and_pager_assigns(
      String.to_integer(page_num),
      socket.assigns.audit_pager.page_size
    )
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event(_name, _params, socket), do: {:cont, socket}

  def hooked_info(_name, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}
end
