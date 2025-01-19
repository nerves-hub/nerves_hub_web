defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:fwup_progress, :any)

  def render(assigns) do
    ~H"""
    <div class="sticky top-0 w-full h-0 overflow-visible z-20">
      <div class="absolute border-0 border-t-[1px] border-success-500" role="progressbar" style={"width: #{@fwup_progress}%"}>
        <div class="animate-pulse bg-progress-glow w-full h-16" />
      </div>
      <div class="text-center pt-2 text-sm animate-pulse">Updating firmware {@fwup_progress}%</div>
    </div>
    """
  end
end
