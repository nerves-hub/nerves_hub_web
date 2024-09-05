defmodule NervesHubWeb.Components.HealthSection do
  use NervesHubWeb, :component

  attr(:title, :string)
  attr(:svg, :any)
  attr(:memory_size, :any, default: nil)
  attr(:memory_usage, :any, default: nil)

  def render(assigns) do
    ~H"""
    <div class="metrics-section">
      <div class="help-text mb-1">
        <%= @title %>
        <div :if={@memory_size}>Currently using <%= @memory_usage %>% of <%= @memory_size %> MB.</div>
      </div>
      <div>
        <%= @svg %>
      </div>
    </div>
    """
  end
end
