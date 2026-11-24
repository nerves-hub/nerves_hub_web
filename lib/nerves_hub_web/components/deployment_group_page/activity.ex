defmodule NervesHubWeb.Components.DeploymentGroupPage.Activity do
  @moduledoc """
  A deployment group's Activity tab: its audit log, newest first, a day at a
  time, drawn as the device page's Activity tab is.

  Group entries carry no `kind`, so each row's glyph says who wrote it: a
  member, a device (whose identifier links to it), or the group itself when
  its workflow did something on its own. A description's first line is its
  headline; anything after it is the detail under it.

  An entry written from a `NervesHub.AuditLogs.Template` names its users,
  devices and deployment groups as they are now, linked when the viewer can
  open them (`NervesHubWeb.Components.AuditLogDescription`). Its template is
  split into headline and detail rather than its description, so a value
  with a line break in it stays where it was put.

  The page and page size come from the URL (`page`, read by the LiveView's
  `handle_params/3`), so the page's refresh every few seconds keeps the page
  being read, and a link to page 3 opens on page 3.
  """
  use NervesHubWeb, :live_component

  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHubWeb.Components.AuditLogDescription
  alias NervesHubWeb.Components.Pager

  # The sizes `Pager.footer/1` offers.
  @page_sizes [25, 50, 100]

  @doc """
  The page and page size `params` ask for, as the tab reads them. A size
  the pager doesn't offer is the smallest it does.
  """
  @spec page_params(map()) :: %{page: pos_integer(), page_size: pos_integer()}
  def page_params(params) do
    size = NervesHub.ListQuery.positive_integer(params["page_size"], hd(@page_sizes))

    %{
      page: NervesHub.ListQuery.positive_integer(params["page_number"], 1),
      page_size: if(size in @page_sizes, do: size, else: hd(@page_sizes))
    }
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> load_activity()
    |> ok()
  end

  defp load_activity(socket) do
    %{deployment_group: deployment_group, page: %{page: page, page_size: page_size}} = socket.assigns

    {logs, pager} = AuditLogs.logs_for_feed(deployment_group, %{page: page, page_size: page_size})
    %{org: org, user: user} = socket.assigns.current_scope

    assign(socket,
      activity: logs,
      devices: AuditLogs.actor_devices(logs),
      references: AuditLogs.load_references(logs, org, user),
      audit_pager: Map.from_struct(pager)
    )
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :days, group_by_day(assigns.activity, assigns.time_zone))

    ~H"""
    <div id="deployment-group-activity" class="p-4 sm:p-6">
      <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <div class="flex h-12 shrink-0 items-center justify-between gap-3 pr-3 pl-4">
          <div class="flex min-w-0 items-baseline gap-2.5">
            <h2 class="text-sm/4.5 font-semibold text-content-strong">Activity</h2>
            <span class="hidden truncate text-xs text-content-faint sm:inline">What people, devices and the group itself did</span>
          </div>

          <.button
            type="link"
            size="sm"
            aria-label="Download activity"
            href={~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@deployment_group}/audit_logs/download"}
          >
            <span class="lucide-download" aria-hidden="true"></span> Download CSV
          </.button>
        </div>

        <div :if={@days == []} class="flex items-center justify-center border-t border-line-subtle p-14">
          <span class="text-ui text-content-faint">
            {if @audit_pager.total_count == 0, do: "Nothing has happened in this deployment group yet.", else: "Nothing on this page."}
          </span>
        </div>

        <div :if={@days != []} class="flex flex-col px-4 pb-1.5">
          <section :for={{day, entries} <- @days} aria-label={day}>
            <h3 class="flex h-8.5 items-center border-t border-line-subtle pt-1.5 text-label font-medium text-content-faint uppercase">
              {day}
            </h3>
            <ul>
              <li :for={{entry, {headline, detail}} <- entries} data-activity-entry class="flex min-h-11 items-center gap-3 py-1.5">
                <span class="flex size-7 shrink-0 items-center justify-center rounded-full border border-line-subtle bg-surface-muted">
                  <span class={[actor_icon(entry.actor_type), "size-3.5 text-content-muted"]} aria-hidden="true"></span>
                </span>

                <div class="flex min-w-0 grow flex-col gap-0.5">
                  <%!-- A description can hold an unbroken token (a firmware
                        UUID), which breaks rather than running under the time. --%>
                  <p class="text-ui/4.5 wrap-break-word text-content-body">
                    <%!-- A template names the device itself. --%>
                    <.device_identifier
                      :if={entry.actor_type == Device && entry.template == nil && @devices[entry.actor_id]}
                      device={@devices[entry.actor_id]}
                      path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices/#{@devices[entry.actor_id].identifier}"}
                    />
                    <AuditLogDescription.description entry={entry} text={headline} references={@references} scope={@current_scope} current={@deployment_group} />
                  </p>
                  <p :if={detail} class="text-xs/4.5 wrap-break-word text-content-muted">
                    <AuditLogDescription.description entry={entry} text={detail} references={@references} scope={@current_scope} current={@deployment_group} />
                  </p>
                </div>

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

        <Pager.footer id="activity-pager" pager={@audit_pager} phx-target={@myself} />
      </div>
    </div>
    """
  end

  # Who wrote an entry, in the bold weight a 14px glyph takes, as the device
  # Activity tab draws an entry's kind. Whole class names, so Tailwind finds
  # them. The description names who it was.
  defp actor_icon(DeploymentGroup), do: "lucide-workflow--bold"
  defp actor_icon(Device), do: "lucide-cpu--bold"
  defp actor_icon(_), do: "lucide-user--bold"

  attr(:device, :map, required: true)
  attr(:path, :string, required: true)

  # The device a device's entry is about, which its description doesn't name.
  defp device_identifier(%{device: %{deleted?: true}} = assigns) do
    ~H"""
    <span class="font-mono text-content-strong">{@device.identifier}</span><span class="text-content-faint"> · </span>
    """
  end

  defp device_identifier(assigns) do
    ~H"""
    <.link navigate={@path} class="font-mono text-notice-content hover:underline">{@device.identifier}</.link><span class="text-content-faint"> · </span>
    """
  end

  @doc false
  # An entry's first line, and the rest joined into one line under it, or nil.
  # Takes a description or a template, whose placeholders hold no spaces.
  # Public so the tests can pin how stored descriptions split.
  @spec split_description(String.t()) :: {String.t(), String.t() | nil}
  def split_description(description) do
    description
    |> String.trim()
    |> String.split("\n", parts: 2)
    |> case do
      [headline] -> {headline, nil}
      [headline, rest] -> {headline, rest |> String.split() |> Enum.join(" ")}
    end
  end

  # Entries arrive newest first, so each day's run is already in order. Each
  # entry comes with its description split for drawing.
  defp group_by_day(entries, time_zone) do
    entries
    |> Enum.chunk_by(&day_key(&1.inserted_at, time_zone))
    |> Enum.map(fn [first | _] = day ->
      {to_local_string(first.inserted_at, time_zone, :medium_date, false),
       Enum.map(day, &{&1, split_description(&1.template || &1.description)})}
    end)
  end

  @impl Phoenix.LiveComponent
  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> push_patch(to: activity_path(socket, 1, page_size))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page}, socket) do
    socket
    |> push_patch(to: activity_path(socket, page, socket.assigns.audit_pager.page_size))
    |> noreply()
  end

  defp activity_path(socket, page, page_size) do
    %{current_scope: %{org: org, product: product}, deployment_group: deployment_group} = socket.assigns
    params = %{"page_number" => page, "page_size" => page_size}

    ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/activity?#{params}"
  end
end
