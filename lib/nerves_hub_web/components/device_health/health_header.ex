defmodule NervesHubWeb.Components.HealthHeader do
  use NervesHubWeb, :component

  attr(:org, :any)
  attr(:product, :any)
  attr(:device, :any)
  attr(:status, :any)

  def render(assigns) do
    ~H"""
    <h1 class="ff-m mt-2 mb-1">Device Health</h1>
    <p class="help-text large">Device identifier: <%= @device.identifier %></p>


    <div class="device-meta-grid">
      <div>
        <div class="help-text">Status</div>
        <p class="flex-row align-items-center tt-c">
          <span><%= @status %></span>
          <span class="ml-1">
            <%= if @status in ["offline"] do %>
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
          <span class="tooltip-info"></span>
          <span class="tooltip-text" id="connection-establisted-at-tooltip" phx-hook="LocalTime">
            <%= @device.connection_established_at %>
          </span>
        </div>
        <p>
          <span :if={!@device.connection_established_at}>Never</span>
          <time
            :if={@device.connection_established_at}
            id="connection-establisted-at"
            phx-hook="UpdatingTimeAgo"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.connection_established_at, :second)), " ", "T")}
          >
            <%= Timex.from_now(@device.connection_established_at) %>
          </time>
        </p>
      </div>
      <div>
        <div class="help-text mb-1 tooltip-label help-tooltip">
          <span>Last seen</span>
          <span class="tooltip-info"></span>
          <span class="tooltip-text" id="connection-last-seen-at-tooltip" phx-hook="LocalTime">
            <%= @device.connection_last_seen_at %>
          </span>
        </div>
        <p>
          <span :if={!@device.connection_last_seen_at}>Never</span>
          <time
            :if={@device.connection_last_seen_at}
            id="last-communication-at"
            phx-hook="UpdatingTimeAgo"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.connection_last_seen_at, :second)), " ", "T")}
          >
            <%= Timex.from_now(@device.connection_last_seen_at) %>
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
        <div class="help-text mb-1">Platform</div>
        <%= if is_nil(@device.firmware_metadata.platform) do %>
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
end
