defmodule NervesHubWeb.Components.DevicePage.ActivityTab do
  use NervesHubWeb, tab_component: :activity

  alias NervesHub.AuditLogs
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
    assigns = assign(assigns, :days, group_by_day(assigns.activity, assigns.time_zone))

    ~H"""
    <div
      id="activity-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex h-full flex-col items-start justify-between gap-4 opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <div class="w-full p-4 sm:p-6">
        <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
          <div class="flex h-12 shrink-0 items-center justify-between gap-3 pr-3 pl-4">
            <div class="flex min-w-0 items-baseline gap-2.5">
              <h2 class="text-sm/4.5 font-semibold text-content-strong">Activity</h2>
              <span class="hidden truncate text-xs text-content-faint sm:inline">What people, deployments and the device itself did</span>
            </div>

            <.button type="link" size="sm" aria-label="Download activity" href={~p"/org/#{@org}/#{@product}/devices/#{@device}/audit_logs/download"}>
              <span class="lucide-download" aria-hidden="true"></span> Download CSV
            </.button>
          </div>

          <div :if={@days == []} class="flex items-center justify-center border-t border-line-subtle p-14">
            <span class="text-ui text-content-faint">No audit logs found for the device.</span>
          </div>

          <div :if={@days != []} class="flex flex-col px-4 pb-1.5">
            <section :for={{day, entries} <- @days} aria-label={day}>
              <h3 class="flex h-8.5 items-center border-t border-line-subtle pt-1.5 text-label font-medium tracking-[0.06em] text-content-faint uppercase">
                {day}
              </h3>
              <ul>
                <li :for={entry <- entries} data-activity-entry class="flex min-h-11 items-center gap-3 py-1.5">
                  <span class="flex size-7 shrink-0 items-center justify-center rounded-full border border-line-subtle bg-surface-muted">
                    <span class={[kind_icon(entry.kind), "size-3.5 text-content-muted"]} aria-hidden="true"></span>
                  </span>
                  <%!-- A description can hold an unbroken token (a shared secret's
                        key, a firmware UUID), which breaks rather than running
                        under the time. --%>
                  <span class="min-w-0 grow text-ui/4.5 wrap-break-word text-content-body">{entry.description}</span>
                  <.local_datetime
                    at={entry.inserted_at}
                    time_zone={@time_zone}
                    format={:time}
                    zone_label={false}
                    class="shrink-0 text-xs whitespace-nowrap text-content-faint"
                  />
                </li>
              </ul>
            </section>
          </div>

          <Pager.footer id="activity-pager" pager={@audit_pager} />
        </div>
      </div>
    </div>
    """
  end

  # Entries arrive newest first, so each day's run is already in order.
  defp group_by_day(entries, time_zone) do
    entries
    |> Enum.chunk_by(&day_key(&1.inserted_at, time_zone))
    |> Enum.map(fn [first | _] = day ->
      {to_local_string(first.inserted_at, time_zone, :medium_date, false), day}
    end)
  end

  # One glyph per kind of entry (`NervesHub.AuditLogs.AuditLog.kinds/0`), as
  # the Activity tab boards in Paper draw them, in the bold weight a 14px glyph
  # takes. Whole class names, so Tailwind finds them. Entries written before
  # kinds existed have none and get the neutral glyph.
  @icons %{
    archive_sent: "lucide-archive--bold",
    deployment_group_mismatch: "lucide-unlink--bold",
    deployment_group_set: "lucide-rocket--bold",
    deployment_update_sent: "lucide-download--bold",
    device_moved: "lucide-arrow-right-left--bold",
    device_rebooted: "lucide-power--bold",
    device_updated: "lucide-pencil--bold",
    firmware_metadata_updated: "lucide-file-text--bold",
    firmware_pushed: "lucide-download--bold",
    firmware_updated: "lucide-refresh-cw--bold",
    firmware_validated: "lucide-shield-check--bold",
    identify_requested: "lucide-locate--bold",
    managed_updates_changed: "lucide-cpu--bold",
    penalty_box_cleared: "lucide-lock-open--bold",
    reconnect_requested: "lucide-wifi--bold",
    script_run: "lucide-file-code-corner--bold",
    shared_secret_created: "lucide-key-round--bold",
    shared_secret_deactivated: "lucide-key-round--bold",
    tags_changed: "lucide-tag--bold",
    update_attempted: "lucide-hard-drive-download--bold",
    update_failed: "lucide-triangle-exclamation-point--bold",
    update_ignored: "lucide-circle-slash--bold",
    update_mode_changed: "lucide-sliders-horizontal--bold",
    update_requested: "lucide-download--bold",
    update_rescheduled: "lucide-calendar-clock--bold",
    updates_blocked: "lucide-ban--bold",
    updates_disabled: "lucide-toggle-left--bold",
    updates_enabled: "lucide-toggle-right--bold"
  }

  @doc false
  # The glyph class for an entry's kind; public so the tests can check every
  # kind has one.
  @spec kind_icon(atom() | nil) :: String.t()
  def kind_icon(kind), do: Map.get(@icons, kind, "lucide-activity--bold")

  @decorate requires_membership()
  def hooked_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => "1"}

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/activity?#{params}"

    socket
    |> logs_and_pager_assigns(1, String.to_integer(page_size))
    |> push_patch(to: url)
    |> halt()
  end

  @decorate requires_membership()
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

  @decorate requires_membership()
  def hooked_event(_name, _params, socket), do: {:cont, socket}

  def hooked_info(_name, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}
end
