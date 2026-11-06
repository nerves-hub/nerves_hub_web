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
        <h1 class="text-page-title text-content-strong">My Pinned Devices</h1>
      </div>
      <div class="rounded-md border border-line-default bg-surface-raised">
        <div class="flex flex-col">
          <div class="listing">
            <table class="">
              <thead>
                <tr>
                  <th class="rounded-tl-md">Identifier</th>
                  <th>Health</th>
                  <th>Firmware</th>
                  <th>Platform</th>
                  <th>Tags</th>
                  <th class="rounded-tr-md">Project</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={device <- @devices} class="relative border-b border-line-subtle last:rounded-b-md last:border-0">
                  <td>
                    <div class="flex items-center gap-[8px]">
                      <span title="status">
                        <%= if @statuses[device.identifier] == "online" do %>
                          <.status_dot class="bg-status-online" />
                        <% else %>
                          <.status_dot class="bg-status-offline" />
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
                      <span :if={device.firmware_metadata && device.update_mode != :off} class="lucide-shield-check size-4 text-success" title="Updates enabled"></span>
                      <span :if={device.firmware_metadata && device.update_mode == :off} class="lucide-shield-off size-4 text-content-muted" title="Updates disabled"></span>
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
                          <.tag>{tag}</.tag>
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

          <div :if={@total_count > @device_limit} phx-click="toggle-expand-devices" class="px-6 py-2 text-center text-xs font-normal text-content-muted hover:cursor-pointer hover:text-content-strong">
            {if @show_all?, do: "Show less", else: "Show all #{@total_count} devices"}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
