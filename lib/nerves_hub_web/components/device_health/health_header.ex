defmodule NervesHubWeb.Components.HealthHeader do
  use NervesHubWeb, :component

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection

  attr(:org_name, :string)
  attr(:product_name, :string)
  attr(:device, Device)
  attr(:latest_connection, DeviceConnection)
  attr(:health_reported_at, DateTime)
  attr(:health_check_timer, :any, default: nil)

  def render(assigns) do
    ~H"""
    <div class="action-row">
      <div>
        <h1 class="ff-m mt-2 mb-1">Device Health</h1>
        <p class="help-text large">Device identifier: <%= @device.identifier %></p>
      </div>
      <div>
        <button
          class="btn btn-outline-light btn-action"
          aria-label={if @health_check_timer, do: "Disable Auto Refresh", else: "Enable Auto Refresh"}
          type="button"
          phx-click="toggle-health-check-auto-refresh"
        >
          <span :if={@health_check_timer} class="action-text">Disable Auto Refresh</span>
          <span :if={!@health_check_timer} class="action-text">Enable Auto Refresh</span>
        </button>
      </div>
    </div>
    <div class="device-meta-grid">
      <div>
        <div class="help-text">Status</div>
        <p class="flex-row align-items-center tt-c">
          <span><%= get_status(@latest_connection) %></span>
          <span class="ml-1">
            <%= if get_status(@latest_connection) in ["offline"] do %>
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
          <span :if={@latest_connection} class="tooltip-info"></span>
          <span :if={@latest_connection} class="tooltip-text" id="connection-establisted-at-tooltip" phx-hook="LocalTime">
            <%= @latest_connection.established_at %>
          </span>
        </div>
        <p>
          <span :if={!@latest_connection}>Never</span>
          <time :if={@latest_connection} id="connection-established-at" phx-hook="UpdatingTimeAgo" datetime={format_time(@latest_connection.established_at)}>
            <%= Timex.from_now(@latest_connection.established_at) %>
          </time>
        </p>
      </div>
      <div>
        <div class="help-text mb-1 tooltip-label help-tooltip">
          <span>Last reported</span>
          <span :if={@health_reported_at} class="tooltip-info"></span>
          <span :if={@health_reported_at} class="tooltip-text" id="last-reported-at-tooltip" phx-hook="LocalTime">
            <%= @health_reported_at %>
          </span>
        </div>
        <p>
          <span :if={!@health_reported_at}>Never</span>
          <time :if={@health_reported_at} id="last-reported-at" phx-hook="UpdatingTimeAgo" datetime={format_time(@health_reported_at)}>
            <%= Timex.from_now(@health_reported_at) %>
          </time>
        </p>
      </div>
      <div>
        <div class="help-text mb-1">Version</div>
        <%= if is_nil(@device.firmware_metadata) do %>
          <p>Unknown</p>
        <% else %>
          <.link navigate={~p"/org/#{@org_name}/#{@product_name}/firmware/#{@device.firmware_metadata.uuid}"} class="badge ff-m mt-0">
            <%= @device.firmware_metadata.version %> (<%= String.slice(@device.firmware_metadata.uuid, 0..7) %>)
          </.link>
        <% end %>
      </div>
      <div>
        <div class="help-text mb-1">Platform</div>
        <%= if is_nil(@device.firmware_metadata) do %>
          <p>Unknown</p>
        <% else %>
          <p class="badge ff-m mt-0">
            <%= @device.firmware_metadata.platform %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_status(%{status: :connected}), do: "online"
  defp get_status(_), do: "offline"

  defp format_time(timestamp) do
    timestamp
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace(" ", "T")
  end
end
