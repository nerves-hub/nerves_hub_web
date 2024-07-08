defmodule NervesHubWeb.Components.DeviceHeader do
  use NervesHubWeb, :component

  alias NervesHub.Devices

  alias NervesHubWeb.LayoutView.DateTimeFormat

  attr(:org, :any)
  attr(:product, :any)
  attr(:device, :any)
  attr(:status, :any)

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
        <div class="help-text mb-1">Version</div>
        <%= if is_nil(@device.firmware_metadata) do %>
          <p>Unknown</p>
        <% else %>
          <.link navigate={~p"/org/#{@org.name}/#{@product.name}/firmware/#{@device.firmware_metadata.uuid}"} class="badge ff-m mt-0">
            <%= @device.firmware_metadata.version %>
            <%= @device.firmware_metadata.uuid %>
          </.link>
        <% end %>
      </div>
      <div>
        <div class="help-text mb-1 tooltip-label help-tooltip">
          <span>Last Handshake</span>
          <span class="tooltip-info"></span>
          <span class="tooltip-text"><%= @device.last_communication %></span>
        </div>
        <p>
          <%= if is_nil(@device.last_communication) do %>
            Never
          <% else %>
            <%= DateTimeFormat.from_now(@device.last_communication) %>
          <% end %>
        </p>
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

    <%= if Map.has_key?(assigns, :fwup_progress) && assigns.fwup_progress do %>
      <div class="help-text mt-3">Progress</div>
      <div class="progress device-show">
        <div class="progress-bar" role="progressbar" style={"width: #{@fwup_progress}%"}>
          <%= @fwup_progress %>%
        </div>
      </div>
    <% end %>

    <div class="divider"></div>
    """
  end
end
