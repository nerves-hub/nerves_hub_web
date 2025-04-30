defmodule NervesHubWeb.Components.PinnedDevices do
  use NervesHubWeb, :component

  alias NervesHubWeb.Components.HealthStatus

  attr(:devices, :list, required: true)
  attr(:statuses, :map, required: true)
  attr(:device_limit, :integer, required: true)
  attr(:total_count, :integer, required: true)
  attr(:show_all?, :boolean, default: false)

  def render(assigns) do
    ~H"""
    <div>
      <div class="mt-12 h-[88px] py-6 flex items-center justify-between">
        <h1 class="text-xl leading-[30px] font-semibold text-neutral-50">My Pinned Devices</h1>
      </div>
      <div class="bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex flex-col">
          <div class="listing">
            <table class="">
              <thead>
                <tr>
                  <th>Identifier</th>
                  <th>Health</th>
                  <th>Firmware</th>
                  <th>Platform</th>
                  <th>Tags</th>
                  <th>Project</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={device <- @devices} class="border-b border-zinc-800 relative">
                  <td>
                    <div class="flex gap-[8px] items-center">
                      <span title="status">
                        <%= if @statuses[device.identifier] == "online" do %>
                          <svg xmlns="http://www.w3.org/2000/svg" width="6" height="6" viewBox="0 0 6 6" fill="none">
                            <circle cx="3" cy="3" r="3" fill="#10B981" />
                          </svg>
                        <% else %>
                          <svg xmlns="http://www.w3.org/2000/svg" width="6" height="6" viewBox="0 0 6 6" fill="none">
                            <circle cx="3" cy="3" r="3" fill="#71717A" />
                          </svg>
                        <% end %>
                      </span>
                      <.link navigate={~p"/org/#{device.org.name}/#{device.product.name}/devices/#{device.identifier}"} class="ff-m ">
                        {device.identifier}
                      </.link>
                    </div>
                  </td>

                  <td>
                    <div class="flex gap-[8px] items-center justify-center">
                      <HealthStatus.render device_id={device.id} health={device.latest_health} />
                    </div>
                  </td>

                  <td>
                    <div class="flex gap-[8px] items-center">
                      <span>
                        <%= if is_nil(device.firmware_metadata) do %>
                          -
                        <% else %>
                          {device.firmware_metadata.version}
                        <% end %>
                      </span>
                      <svg :if={device.firmware_metadata && device.updates_enabled} title="Updates enabled" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path
                          d="M6.00016 8L7.3335 9.33333L10.0002 6M8.00016 14C8.00016 14 12.6668 12 12.6668 9.33333V3.33333C11.6668 3.44444 9.3335 3.33333 8.00016 2C6.66683 3.33333 4.3335 3.44444 3.3335 3.33333V9.33333C3.3335 12 8.00016 14 8.00016 14Z"
                          stroke="#10B981"
                          stroke-width="1.2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        />
                      </svg>
                      <svg :if={device.firmware_metadata && not device.updates_enabled} title="Updates disabled" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path
                          d="M12.6667 9.33333V3.33333C11.6667 3.44444 9.33333 3.33333 8 2C7.61905 2.38095 7.15646 2.66213 6.66667 2.86686M3.33333 3.33333V9.33333C3.33333 12 8 14 8 14C8 14 10.1359 13.0846 11.5177 11.6667M2 2L14 14"
                          stroke="#A1A1AA"
                          stroke-width="1.2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        />
                      </svg>
                    </div>
                  </td>

                  <td>
                    <span>
                      <%= if is_nil(device.firmware_metadata) do %>
                        -
                      <% else %>
                        {device.firmware_metadata.platform}
                      <% end %>
                    </span>
                  </td>

                  <td class="max-w-[250px] scrollable-table-cell">
                    <div class="flex items-center text-nowrap gap-[4px]">
                      <%= if !is_nil(device.tags) do %>
                        <%= for tag <- device.tags do %>
                          <span class="tag">{tag}</span>
                        <% end %>
                      <% end %>
                    </div>
                  </td>
                  <td>
                    <div class="org-selector-title">{device.org.name}</div>
                    <div class="product-selector-title flex gap-2 items-center">
                      <span>{device.product.name}</span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@total_count > @device_limit} phx-click="toggle-expand-devices" class="px-6 py-2 text-center text-xs font-normal text-zinc-400  hover:text-neutral-50 hover:cursor-pointer">
            {if @show_all?, do: "Show less", else: "Show all #{@total_count} devices"}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
