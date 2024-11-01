defmodule NervesHubWeb.Components.HealthSection do
  use NervesHubWeb, :component

  attr(:title, :string)
  attr(:chart, :any)
  attr(:memory_size, :any, default: nil)
  attr(:memory_usage, :any, default: nil)

  def render(assigns) do
    ~H"""
    <div class="metrics-section">
      <div class="help-text mb-1">
        <%= @title %>
        <%= if (@chart.type == "used_mb") do %>
          <div>Currently using <%= @memory_usage %>% of <%= @memory_size %> MB.</div>
        <% end %>
      </div>
      <div>
        <div style="margin-bottom: 100px;">
          <canvas
            id={@chart.type}
            style="display: block; box-sizing: border-box;"
            width="1200"
            height="600"
            phx-hook="Chart"
            phx-update="ignore"
            data-type={Jason.encode!(@chart.type)}
            data-unit={Jason.encode!(@chart.unit)}
            data-max={Jason.encode!(@chart.max)}
            data-metrics={Jason.encode!(@chart.data)}
          >
          </canvas>
        </div>
      </div>
    </div>
    """
  end
end
