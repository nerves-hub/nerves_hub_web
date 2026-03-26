defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:fwup_progress, :any)

  def render(assigns) do
    ~H"""
    <div class="help-text mt-3">Progress</div>
    <div class="device-show progress">
      <div class="progress-bar" role="progressbar" style={"width: #{@fwup_progress}%"}>
        {@fwup_progress}%
      </div>
    </div>
    """
  end

  attr(:fwup_progress, :any)

  def updated_render(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 h-0 w-full overflow-visible">
      <div class="border-success-500 absolute z-40 border-t" role="progressbar" style={"width: #{@fwup_progress}%"}>
        <div class="bg-progress-glow h-16 w-full animate-pulse" />
      </div>
      <div class="absolute z-50 flex w-full justify-center">
        <div class="bg-surface-muted/20 mt-1 rounded-full px-2 py-1 text-sm font-medium">Updating firmware {@fwup_progress}%</div>
      </div>
    </div>
    """
  end
end
