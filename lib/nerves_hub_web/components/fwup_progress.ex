defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:fwup_progress, :any)

  def render(assigns) do
    ~H"""
    <div class="help-text mt-3">Progress</div>
    <div class="progress device-show">
      <div class="progress-bar" role="progressbar" style={"width: #{@fwup_progress}%"}>
        <%= @fwup_progress %>%
      </div>
    </div>
    """
  end
end
