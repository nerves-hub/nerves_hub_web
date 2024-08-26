defmodule NervesHubWeb.Components.HealthSection do
  use NervesHubWeb, :component

  attr(:title, :string)
  attr(:svg, :any)

  def render(assigns) do
    ~H"""
    <div class="metrics-section">
        <div class="help-text mb-1"><%= @title %></div>
        <div class="metrics-text">
          <%= @svg %>
        </div>
      </div>
    """
  end
end
