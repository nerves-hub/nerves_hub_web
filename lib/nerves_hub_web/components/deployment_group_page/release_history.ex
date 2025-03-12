defmodule NervesHubWeb.Components.DeploymentGroupPage.ReleaseHistory do
  use NervesHubWeb, :live_component

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center gap-4">
      <div class="font-semibold text-xl">
        Coming Soon...
      </div>
    </div>
    """
  end
end
