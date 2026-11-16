defmodule NervesHubWeb.Components.DevicePage.TabNotice do
  @moduledoc """
  What a device page tab shows in place of its content when it has none to
  show for a reason the reader can act on, such as an extension that is turned
  off: a card holding what is wrong and where to look.
  """

  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:detail, :string, required: true)

  def render(assigns) do
    ~H"""
    <div class="w-full p-4 sm:p-6">
      <div class="flex flex-col items-center justify-center gap-1 rounded-card border border-line-default bg-surface-raised p-14 text-center shadow-card">
        <div class="text-ui font-medium text-content-strong">{@title}</div>
        <div class="text-xs text-content-faint">{@detail}</div>
      </div>
    </div>
    """
  end
end
