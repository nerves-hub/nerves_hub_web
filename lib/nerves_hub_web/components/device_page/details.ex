defmodule NervesHubWeb.Components.DevicePage.Details do
  use NervesHubWeb, :live_component

  alias NervesHub.Firmwares
  alias NervesHub.Scripts

  alias NervesHubWeb.Components.DeviceLocation

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_support_scripts()
    |> assign(:firmwares, Firmwares.get_firmware_for_device(assigns.device))
    |> ok()
  end

  defp assign_support_scripts(socket) do
    scripts =
      socket.assigns.product
      |> Scripts.all_by_product()
      |> Enum.map(&Map.merge(&1, %{:output: nil, running?: false}))

    assign(socket, :support_scripts, scripts)
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-4 p-6">
      <div class="w-1/2 flex flex-col gap-4">
        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center justify-between">
            <div class="text-neutral-50 font-medium leading-6">Health</div>
            <div class="flex items-center gap-2">
              <div class="text-xs text-zinc-300 tracking-wide">Auto refresh</div>
              <div>
                <button
                  type="button"
                  phx-click="toggle-health-check-auto-refresh"
                  class={[
                    "relative inline-flex items-center h-3.5 w-6 shrink-0 cursor-pointer rounded-full border-1.5 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:ring-offset-2",
                    (@auto_refresh_health && "bg-indigo-500") || "bg-gray-200"
                  ]}
                  role="switch"
                  aria-checked="false"
                >
                  <span class="sr-only">Auto refresh health information</span>
                  <span
                    aria-hidden="true"
                    class={[
                      "pointer-events-none inline-block size-3",
                      (@auto_refresh_health && "translate-x-3") || "translate-x-0",
                      "transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
                    ]}
                  >
                  </span>
                </button>
              </div>
            </div>
          </div>
          <div class="flex pt-2 px-4 pb-6 gap-2 items-center">
            <div class="w-20 flex flex-col h-16 py-2 px-3 rounded border-b border-emerald-500 bg-health-good">
              <span class="text-xs text-zinc-400 tracking-wide">CPU</span>
              <span class="text-xl leading-[30px] text-neutral-50">43°</span>
            </div>
            <div class="w-1/2 flex flex-col h-16 py-2 px-3 rounded border-b border-amber-500 bg-health-warning">
              <span class="text-xs text-zinc-400 tracking-wide">Memory used</span>
              <div class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">136 mb</span>
                <span class="text-base text-amber-500">44%</span>
              </div>
            </div>
            <div class="w-1/2 flex flex-col h-16 py-2 px-3 rounded border-b border-indigo-500 bg-health-netural">
              <span class="text-xs text-zinc-400 tracking-wide">Load avg</span>
              <div class="flex justify-between items-center">
                <span class="text-xl leading-[30px] text-neutral-50">0.02</span>
                <div class="flex w-4 items-center justify-center gap-2">
                  <span class="w-px h-4 bg-zinc-700"></span>
                </div>
                <span class="text-xl leading-[30px] text-neutral-50">0.01</span>
                <span class="w-px h-4 bg-zinc-700"></span>
                <span class="text-xl leading-[30px] text-neutral-50">0.03</span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            General info
          </div>
          <div class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">Tags:</span>
            <span :if={is_nil(@device.tags)} class="text-sm text-nerves-gray-500">No Tags</span>
            <span :if={@device.tags} class="flex gap-1">
              <span :for={tag <- @device.tags || []} class="text-sm text-zinc-300 px-2 py-1 border border-zinc-800 bg-zinc-800 rounded" class=""><%= tag %></span>
            </span>
          </div>
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            Deployments
          </div>
          <div class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">Assigned deployment:</span>
            <span :if={is_nil(@deployment)} class="text-sm text-nerves-gray-500">No assigned deployment</span>
            <.link
              :if={@deployment}
              navigate={~p"/org/#{@org.name}/#{@product.name}/deployments/#{@deployment.name}"}
              class="flex items-center gap-1 pl-1.5 pr-2.5 py-0.5 border border-zinc-700 rounded-full bg-zinc-800"
            >
              <svg class="w-1.5 h-1.5" viewBox="0 0 6 6" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="3" cy="3" r="3" fill="#10B981" />
              </svg>
              <span class="text-xs text-zinc-300 tracking-tight" class=""><%= @deployment.name %></span>
            </.link>

            <button
              class="p-1 border border-red-500 rounded-full bg-zinc-800"
              data-confirm="Are you sure you want to remove the device from the deployment?"
              aria-label="Remove device from the assigned deployment"
              type="button"
              phx-click="remove-from-deployment"
            >
              <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke="#EF4444"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </button>
          </div>
          <div class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <form :if={Enum.any?(@firmwares)} phx-submit="push-update" class="flex gap-2 items-center w-full">
              <div class="grow grid grid-cols-1">
                <select
                  id="firmware"
                  name="uuid"
                  class="col-start-1 row-start-1 appearance-none border rounded border-zinc-600 bg-zinc-900 py-1.5 pl-3 pr-8 text-sm text-zinc-400 focus:outline focus:outline-1 focus:-outline-offset-1 focus:outline-indigo-500"
                >
                  <option value="">Select a version</option>
                  <option :for={firmware <- @firmwares} value={firmware.uuid}><%= firmware.version %></option>
                </select>
              </div>
              <button
                class="box-content h-5 py-1.5 px-3 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-500 disabled:bg-base-700 disabled:text-base-400"
                aria-label="Send firmware update"
                data-confirm="Are you sure?"
              >
                Send update
              </button>
              <%!-- disabled={disconnected?(@device_connection)} --%>
            </form>
            <div>
              <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M10 12.5V10M10 7.5V7.49167M17.5 10C17.5 14.1421 14.1421 17.5 10 17.5C5.85786 17.5 2.5 14.1421 2.5 10C2.5 5.85786 5.85786 2.5 10 2.5C14.1421 2.5 17.5 5.85786 17.5 10Z"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </div>
          </div>
        </div>

        <div class="flex flex-col rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
          <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
            Support Scripts
          </div>

          <div :if={Enum.empty?(@support_scripts)} class="flex pt-2 px-4 pb-6 gap-4 items-center">
            <span class="text-sm text-nerves-gray-500">No support scripts have been configured.</span>
          </div>

          <div :if={Enum.any?(@support_scripts)} class="flex-col pt-2 px-4 pb-6 gap-4 items-center">
            <div :for={script <- @support_scripts} class="flex flex-col gap-2">
              <div class="flex gap-4">
                <span class="text-base text-zinc-300"><%= script.name %></span>

                <button class="p-1 border border-green-500 rounded-full bg-zinc-800" type="button" disabled={script.running?} phx-target={@myself} phx-click="run-script" phx-value-id={script.id}>
                  <svg class="w-3 h-3 stroke-green-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M8 19V5L18 12L8 19Z" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>

                <button :if={script.output} class="p-1 border border-red-500 rounded-full bg-zinc-800" type="button" phx-target={@myself} phx-click="clear-script-output" phx-value-id={script.id}>
                  <svg class="size-3 stroke-red-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path
                      d="M8 8H16M16 12H8M8 16H12M20 13V6C20 4.89543 19.1046 4 18 4H6C4.89543 4 4 4.89543 4 6V18C4 19.1046 4.89543 20 6 20H13M19 19L21 17M19 19L17 17M19 19L21 21M19 19L17 21"
                      stroke-width="1.2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </button>
              </div>
              <div :if={script.output} class="mt-2">
                <code class="p-3 bg-zinc-800"><%= script.output %></code>
              </div>
            </div>
          </div>

          <div class="flex p-4 gap-4 items-center border-t border-zinc-700">
            <.link navigate={~p"/org/#{@org.name}/#{@product.name}/scripts"} class="box-content h-5 py-1.5 px-3 rounded border border-base-600 bg-zinc-800 text-sm font-medium text-zinc-300">
              Add a support script
            </.link>
          </div>
        </div>
      </div>

      <div class="w-1/2 flex flex-col items-start self-stretch rounded border border-zinc-700 bg-zinc-900 shadow-device-details-content">
        <div class="h-14 pl-4 pr-3 flex items-center text-neutral-50 font-medium leading-6">
          Location
        </div>
        <div class="h-full w-full pt-2 pb-4 px-4">
          <div class="h-full w-full bg-example-map-dark bg-cover bg-center blur-sm"></div>
        </div>
        <DeviceLocation.render :if={@product.extensions.geo and @device.extensions.geo} location={@device.connection_metadata["location"]} />
      </div>
    </div>
    """
  end

  def handle_event("run-script", %{"id" => id}, socket) do
    %{assigns: %{device: device, support_scripts: scripts, org_user: org_user}} = socket

    authorized!(:"support_script:run", org_user)

    script = Enum.find(scripts, fn script -> script.id == id end)

    socket
    |> assign(:support_scripts, update_script(scripts, id, %{running?: true}))
    |> start_async({:run_script, id}, fn -> Scripts.Runner.send(device, script) end)
    |> noreply()
  end

  def handle_event("clear-script-output", %{"id" => id}, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    socket
    |> assign(:support_scripts, update_script(scripts, id, %{output: nil, running?: false}))
    |> noreply()
  end

  def handle_async({:run_script, id}, result, socket) do
    %{assigns: %{support_scripts: scripts}} = socket

    output =
      case result do
        {:ok, output} ->
          output

        e ->
          inspect(e)
      end

    scripts = update_script(scripts, id, %{output: output, running?: false})

    socket
    |> assign(:support_scripts, scripts)
    |> noreply()
  end

  defp update_script(scripts, id, new_info) when is_binary(id) do
    update_script(scripts, String.to_integer(id), new_info)
  end

  defp update_script(scripts, id, new_info) do
    index = Enum.find_index(scripts, fn script -> script.id == id end)

    List.update_at(scripts, index, fn script ->
      Map.merge(script, new_info)
    end)
  end
end
