defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:fwup_progress, :any)

  def render(assigns) do
    ~H"""
    <div class="help-text mt-3">Progress</div>
    <div class="progress device-show">
      <div class="progress-bar" role="progressbar" style={"width: #{@fwup_progress}%"}>
        {@fwup_progress}%
      </div>
    </div>
    """
  end

  attr(:fwup_progress, :any)

  def updated_render(assigns) do
    ~H"""
    <div class="relative sticky top-0 w-full h-0 overflow-visible z-20">
      <div class="z-40 absolute border-0 border-t-[1px] border-success-500" role="progressbar" style={"width: #{@fwup_progress}%"}>
        <div class="animate-pulse bg-progress-glow w-full h-16" />
      </div>
      <div class="z-50 absolute w-full flex justify-center">
        <div class="mt-1 py-1 px-2 bg-base-900/20 rounded-full text-sm font-medium">Updating firmware {@fwup_progress}%</div>
      </div>
    </div>
    """
  end
end
