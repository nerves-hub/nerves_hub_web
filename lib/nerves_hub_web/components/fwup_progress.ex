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
    <div class="flex flex-col w-1/2 pl-4 pr-2">
      <div class="flex justify-between mb-1">
        <span class="text-sm font-base text-indigo-500 dark:text-white">Update in progress</span>
        <span class="text-base font-medium text-indigo-500 dark:text-white">{@fwup_progress}%</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2.5 dark:bg-gray-700">
        <div class="bg-indigo-500 h-2.5 rounded-full animate-pulse" style={"width: #{@fwup_progress}%"}></div>
      </div>
    </div>
    """
  end
end
