defmodule NervesHubWeb.Components.DeploymentGroupPage.Activity do
  use NervesHubWeb, :live_component

  alias NervesHub.AuditLogs
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.Pager

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> logs_and_pager_assigns()
    |> ok()
  end

  defp logs_and_pager_assigns(socket, page_number \\ 1, page_size \\ 25) do
    {logs, audit_pager} =
      AuditLogs.logs_for_feed(socket.assigns.deployment_group, %{
        page: page_number,
        page_size: page_size
      })

    # Use proper links since current pagination links assumes LiveView
    audit_pager =
      audit_pager
      |> Map.from_struct()
      |> Map.put(:links, true)
      |> Map.put(:anchor, "latest-activity")

    socket
    |> assign(:activity, logs)
    |> assign(:audit_pager, audit_pager)
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-full flex-col items-start justify-between gap-4">
      <div class="w-full p-6">
        <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised">
          <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
            <div class="text-card-title text-content-strong">Latest activity</div>

            <.button
              type="link"
              square
              aria-label="Download activity"
              href={~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@deployment_group}/audit_logs/download"}
            >
              <span class="lucide-download size-4" aria-hidden="true"></span>
            </.button>
          </div>
          <div :if={Enum.empty?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div class="flex items-center justify-center p-14">
              <span class="font-extralight text-content-faint">No audit logs found for the deployment group.</span>
            </div>
          </div>
          <div :if={Enum.any?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div :for={entry <- @activity} class="flex h-16 items-center gap-6 p-2">
              <div class="flex h-8 items-center rounded-full border border-line-default bg-base-800 px-2 py-1">
                <span class="lucide-pencil size-4 text-content-muted" aria-hidden="true"></span>
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

      <Pager.render_with_page_sizes pager={@audit_pager} page_sizes={[25, 50, 100]} phx-target={@myself} />
    </div>
    """
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    %{current_scope: %{org: org, product: product}, deployment_group: deployment_group} =
      socket.assigns

    params = %{"page_size" => page_size, "page_number" => 1}

    url =
      ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/activity?#{params}"

    socket
    |> logs_and_pager_assigns(1, String.to_integer(page_size))
    |> push_patch(to: url)
    |> noreply()
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_size" => socket.assigns.audit_pager.page_size, "page_number" => page_num}
    %{current_scope: %{org: org, product: product}, deployment_group: deployment_group} = socket.assigns

    url =
      ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/activity?#{params}"

    socket
    |> logs_and_pager_assigns(
      String.to_integer(page_num),
      socket.assigns.audit_pager.page_size
    )
    |> push_patch(to: url)
    |> noreply()
  end
end
