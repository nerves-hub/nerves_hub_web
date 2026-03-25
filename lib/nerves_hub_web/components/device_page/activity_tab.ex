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
    ~H"""
    <div
      id="activity-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="phx-click-loading:opacity-50 tab-content flex h-full flex-col items-start justify-between gap-4 opacity-0 transition-all duration-500"
    >
      <div class="w-full p-6">
        <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base font-medium text-neutral-50">Latest activity</div>

            <div class="bg-base-800 border-base-600 rounded border p-1.5">
              <.link href={~p"/org/#{@org}/#{@product}/devices/#{@device}/audit_logs/download"}>
                <svg class="size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
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
          <div :if={Enum.empty?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div class="flex items-center justify-center p-14">
              <span class="text-base-500 font-extralight">No audit logs found for the device.</span>
            </div>
          </div>
          <div :if={Enum.any?(@activity)} class="flex flex-col gap-1 px-4 py-2">
            <div :for={entry <- @activity} class="flex h-16 items-center gap-6 p-2">
              <div class="bg-base-800 border-base-700 flex h-8 items-center rounded-full border px-2 py-1">
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
                <div class="text-base-300">{entry.description}</div>
                <div class="flex gap-2">
                  <div class="text-base-400 text-xs tracking-wide">
                    {Timex.from_now(entry.inserted_at)}
                  </div>
                  <div class="flex items-center">
                    <svg class="size-0.5" viewBox="0 0 2 2" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <circle cx="1" cy="1" r="1" fill="#71717A" />
                    </svg>
                  </div>
                  <div class="text-base-400 text-xs tracking-wide">
                    {Calendar.strftime(entry.inserted_at, "%Y-%m-%d at %I:%M:%S %p UTC")}
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
