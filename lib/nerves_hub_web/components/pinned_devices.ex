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
      <div class="mt-12 flex h-[88px] items-center justify-between py-6">
        <h1 class="text-xl leading-[30px] font-semibold text-neutral-50">My Pinned Devices</h1>
      </div>
      <div class="bg-base-900 border-base-700 rounded border">
        <div class="flex flex-col">
          <div class="listing">
            <table class="">
              <thead>
                <tr>
                  <th class="rounded-tl">Identifier</th>
                  <th>Health</th>
                  <th>Firmware</th>
                  <th>Platform</th>
                  <th>Tags</th>
                  <th class="rounded-tr">Project</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={device <- @devices} class="border-base-800 relative border-b last:rounded-b last:border-0">
                  <td>
                    <div class="flex items-center gap-[8px]">
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
                      <.link navigate={~p"/org/#{device.org.name}/#{device.product.name}/devices/#{device.identifier}"} class="ff-m">
                        {device.identifier}
                      </.link>
                    </div>
                  </td>

                  <td>
                    <div class="flex items-center justify-center gap-[8px]">
                      <HealthStatus.render device_id={device.id} health={device.latest_health} />
                    </div>
                  </td>

                  <td>
                    <div class="flex items-center gap-[8px]">
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

                  <td class="relative max-w-[250px]">
                    <span class="pinned-device-tag-gradient-mask" />
                    <div class="scrollable-inner flex items-center gap-[4px] text-nowrap">
                      <%= if !is_nil(device.tags) do %>
                        <%= for tag <- device.tags do %>
                          <span class="tag">{tag}</span>
                        <% end %>
                      <% end %>
                    </div>
                  </td>
                  <td>
                    <div class="org-selector-title">{device.org.name}</div>
                    <div class="product-selector-title flex items-center gap-2">
                      <span>{device.product.name}</span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@total_count > @device_limit} phx-click="toggle-expand-devices" class="text-base-400 px-6 py-2 text-center text-xs font-normal hover:cursor-pointer hover:text-neutral-50">
            {if @show_all?, do: "Show less", else: "Show all #{@total_count} devices"}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
