defmodule NervesHubWeb.Components.DevicePage.FirmwareHistoryTab do
  use NervesHubWeb, tab_component: :firmware_history

  alias NervesHub.Devices.DeviceFirmwares
  alias NervesHubWeb.Components.Pager

  def tab_params(params, _uri, socket) do
    page_number = String.to_integer(Map.get(params, "page_number", "1"))
    page_size = String.to_integer(Map.get(params, "page_size", "25"))

    socket
    |> device_firmwares_and_pager_assigns(page_number, page_size)
    |> cont()
  end

  def cleanup() do
    [:device_firmwares, :device_firmwares_pager]
  end

  defp device_firmwares_and_pager_assigns(socket, page_number, page_size) do
    {history, pager} =
      DeviceFirmwares.paginate(socket.assigns.device, %{
        page: page_number,
        page_size: page_size
      })

    pager = Map.from_struct(pager)

    socket
    |> assign(:device_firmwares, history)
    |> assign(:device_firmwares_pager, pager)
  end

  def render(assigns) do
    ~H"""
    <div
      id="device-firmwares-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="phx-click-loading:opacity-50 tab-content flex h-full flex-col items-start justify-between gap-4 opacity-0 transition-all duration-500"
    >
      <div class="w-full p-6">
        <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Reported Installed Firmwares</div>
          </div>
          <div :if={Enum.empty?(@device_firmwares)} class="flex flex-col gap-1 px-4 py-2">
            <div class="flex items-center justify-center p-14">
              <span class="text-base-500 font-extralight">No firmware history found for the device.</span>
            </div>
          </div>
          <div :if={Enum.any?(@device_firmwares)} class="flex flex-col gap-1 px-4 py-2">
            <div :for={entry <- @device_firmwares} class="flex h-16 items-center gap-6 p-2">
              <div class="bg-base-800 border-base-700 flex h-8 items-center rounded-full border px-2 py-1">
                <span class="lucide-binary--light size-4"></span>
              </div>
              <div class="grow">
                <div id={"device-firmware-#{entry.id}"} class="flex justify-between">
                  <div class="text-base-300">
                    Version: <span class="font-mono">{entry.firmware_metadata.version}</span> <.maybe_with_firmware_link device_firmware={entry} org={@org} product={@product} />
                  </div>
                  <div :if={!entry.firmware_auto_revert_detected} class="bg-base-800 flex items-center rounded px-2 py-1">
                    <span class="text-base-400 mr-1 hidden text-sm lg:block">Firmware:</span>

                    <span :if={entry.firmware_validation_status == :unknown} class="text-base-300 font-mono text-sm">Unknown validation status</span>
                    <span :if={entry.firmware_validation_status == :validated} class="text-base-300 font-mono text-sm">Validated</span>
                    <span :if={entry.firmware_validation_status == :not_validated} class="font-mono text-sm text-red-300">Not validated</span>
                  </div>
                  <div :if={entry.firmware_auto_revert_detected} class="bg-base-800 flex items-center rounded px-2 py-1">
                    <span class="font-mono text-sm text-red-300">Revert detected</span>
                  </div>
                </div>
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

      <Pager.render_with_page_sizes pager={@device_firmwares_pager} page_sizes={[25, 50, 100]} />
    </div>
    """
  end

  defp maybe_with_firmware_link(%{device_firmware: %{firmware_id: nil}} = assigns) do
    ~H"""
    (<span class="font-mono">{String.slice(@device_firmware.firmware_metadata.uuid, 0..7)}</span>) - Firmware unrecognized
    """
  end

  defp maybe_with_firmware_link(assigns) do
    ~H"""
    (<.link navigate={~p"/org/#{@org}/#{@product}/firmware/#{@device_firmware.firmware_metadata.uuid}"} class="font-mono underline">{String.slice(@device_firmware.firmware_metadata.uuid, 0..7)}</.link>)
    """
  end

  def hooked_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => "1"}

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?#{params}"

    socket
    |> device_firmwares_and_pager_assigns(1, String.to_integer(page_size))
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_size" => socket.assigns.device_firmwares_pager.page_size, "page_number" => page_num}

    %{org: org, product: product, device: device} = socket.assigns

    url = ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?#{params}"

    socket
    |> device_firmwares_and_pager_assigns(
      String.to_integer(page_num),
      socket.assigns.device_firmwares_pager.page_size
    )
    |> push_patch(to: url)
    |> halt()
  end

  def hooked_event(_name, _params, socket), do: {:cont, socket}

  def hooked_info(_name, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}
end
