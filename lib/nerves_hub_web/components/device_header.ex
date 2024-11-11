defmodule NervesHubWeb.Components.DeviceHeader do
  use NervesHubWeb, :component

  alias NervesHub.Devices

  attr(:org, :any)
  attr(:product, :any)
  attr(:device, :any)
  attr(:device_connection, :any)

  def render(assigns) do
    ~H"""
    <h1 class="ff-m mt-2 mb-2"><%= @device.identifier %></h1>

    <%= if @device.description do %>
      <p class="help-text large"><%= @device.description %></p>
    <% end %>

    <div class="device-meta-grid">
      <div>
        <div class="help-text">Status</div>
        <p class="flex-row align-items-center tt-c">
          <span><%= get_status(@device_connection) %></span>
          <span class="ml-1">
            <%= if get_status(@device_connection) == "offline" do %>
              <img src="/images/icons/cross.svg" alt="offline" class="table-icon" />
            <% else %>
              <img src="/images/icons/check.svg" alt="online" class="table-icon" />
            <% end %>
          </span>
        </p>
      </div>
      <div>
        <div class="help-text mb-1 tooltip-label help-tooltip">
          <span>Last connected</span>
          <span :if={@device_connection} class="tooltip-info"></span>
          <span :if={@device_connection} class="tooltip-text" id="connection-establisted-at-tooltip" phx-hook="LocalTime">
            <%= @device_connection.established_at %>
          </span>
        </div>
        <p>
          <span :if={!@device_connection}>Never</span>
          <time
            :if={@device_connection}
            id="connection-establisted-at"
            phx-hook="UpdatingTimeAgo"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device_connection.established_at, :second)), " ", "T")}
          >
            <%= Timex.from_now(@device_connection.established_at) %>
          </time>
        </p>
      </div>
      <div>
        <div class="help-text mb-1 tooltip-label help-tooltip">
          <span>Last seen</span>
          <span :if={@device_connection} class="tooltip-info"></span>
          <span :if={@device_connection} class="tooltip-text" id="connection-last-seen-at-tooltip" phx-hook="LocalTime">
            <%= @device_connection.last_seen_at %>
          </span>
        </div>
        <p>
          <span :if={!@device_connection}>Never</span>
          <time
            :if={@device_connection}
            id="last-communication-at"
            phx-hook="UpdatingTimeAgo"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device_connection.last_seen_at, :second)), " ", "T")}
          >
            <%= Timex.from_now(@device_connection.last_seen_at) %>
          </time>
        </p>
      </div>
      <div>
        <div class="help-text mb-1">Version</div>
        <%= if is_nil(@device.firmware_metadata) do %>
          <p>Unknown</p>
        <% else %>
          <.link navigate={~p"/org/#{@org.name}/#{@product.name}/firmware/#{@device.firmware_metadata.uuid}"} class="badge ff-m mt-0">
            <%= @device.firmware_metadata.version %> (<%= String.slice(@device.firmware_metadata.uuid, 0..7) %>)
          </.link>
        <% end %>
      </div>
      <div>
        <div class="help-text">Firmware Updates</div>
        <p>
          <%= cond do %>
            <% @device.updates_enabled == false -> %>
              <span>Disabled</span>
              <span class="ml-1">
                <img src="/images/icons/firmware-disabled.svg" alt="Firmware blocked icon" style="width: 1.3rem; margin-top: -4px;" />
              </span>
            <% Devices.device_in_penalty_box?(@device) -> %>
              <span>In Penalty Box</span>
              <span class="ml-1">
                <img src="/images/icons/firmware-penalty-box.svg" alt="Firmware penalty box icon" style="width: 1.3rem; margin-top: -4px;" />
              </span>
              <a style="" class="btn btn-sm btn-outline-light btn-action" href="#" class="" title="Clear penalty box" aria-label="Clear penalty box" type="button" phx-click="clear-penalty-box">
                Clear
              </a>
            <% true -> %>
              <span>Enabled</span>
              <span class="ml-1">
                <img src="/images/icons/firmware-enabled.svg" alt="Firmware enabled icon" style="width: 1.3rem; margin-top: -4px;" />
              </span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  defp get_status(%{status: :connected}), do: "online"
  defp get_status(_), do: "offline"
end
