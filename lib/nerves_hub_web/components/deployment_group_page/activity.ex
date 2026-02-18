defmodule NervesHubWeb.Components.DeploymentGroupPage.Activity do
  use NervesHubWeb, :live_component

  alias NervesHub.AuditLogs
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
    <div class="h-full flex flex-col items-start justify-between gap-4">
      <div class="p-6 w-full">
        <div class="w-full flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Latest activity</div>

            <div class="p-1.5 rounded bg-zinc-800 border border-zinc-600">
              <.link href={~p"/org/#{@org}/#{@product}/deployment_groups/#{@deployment_group}/audit_logs/download"}>
                <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M2.5 11.6666V14.1666C2.5 15.0871 3.24619 15.8333 4.16667 15.8333H15.8333C16.7538 15.8333 17.5 15.0871 17.5 14.1666V11.6666M10 4.16663V12.5M10 12.5L13.3333 9.16663M10 12.5L6.66667 9.16663"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </.link>
            </div>
          </div>
          <div class="py-2 px-4 flex flex-col gap-1">
            <div :for={entry <- @activity} class="flex items-center gap-6 h-16 p-2">
              <div class="flex items-center h-8 py-1 px-2 bg-zinc-800 border border-zinc-700 rounded-full">
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M8.66663 4.66661L10.1952 3.13801C10.4556 2.87766 10.8777 2.87766 11.138 3.13801L12.8619 4.86187C13.1222 5.12222 13.1222 5.54433 12.8619 5.80468L11.3333 7.33327M8.66663 4.66661L2.86189 10.4713C2.73686 10.5964 2.66663 10.7659 2.66663 10.9427V12.6666C2.66663 13.0348 2.9651 13.3333 3.33329 13.3333H5.05715C5.23396 13.3333 5.40353 13.263 5.52855 13.138L11.3333 7.33327M8.66663 4.66661L11.3333 7.33327M8.66663 13.3333H13.3333"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </div>
              <div class="grow">
                <div class="text-zinc-300">{entry.description}</div>
                <div class="flex gap-2">
                  <div class="text-xs text-zinc-400 tracking-wide">
                    {Timex.from_now(entry.inserted_at)}
                  </div>
                  <div class="flex items-center">
                    <svg class="h-0.5 w-0.5" viewBox="0 0 2 2" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <circle cx="1" cy="1" r="1" fill="#71717A" />
                    </svg>
                  </div>
                  <div class="text-xs text-zinc-400 tracking-wide">
                    {Calendar.strftime(entry.inserted_at, "%Y-%m-%d at %I:%M:%S %p UTC")}
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
    %{org: org, product: product, deployment_group: deployment_group} = socket.assigns

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
    %{org: org, product: product, deployment_group: deployment_group} = socket.assigns

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
