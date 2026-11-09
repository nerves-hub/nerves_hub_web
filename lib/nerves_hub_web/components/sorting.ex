defmodule NervesHubWeb.Components.Sorting do
  use NervesHubWeb, :component

  attr(:field, :any)
  attr(:text, :any)
  attr(:selected_field, :any)
  attr(:selected_direction, :any)

  def sort_icon(assigns) do
    ~H"""
    <div class="group flex items-center whitespace-nowrap">
      {@text}
      <span :if={@selected_field != @field} class="invisible ml-auto lucide-chevrons-up-down size-4 text-base-500 group-hover:visible" aria-hidden="true"></span>
      <span :if={@selected_field == @field && @selected_direction == "asc"} class="ml-auto lucide-chevron-up size-4 text-base-500" aria-hidden="true"></span>
      <span :if={@selected_field == @field && (@selected_direction == "desc" || is_nil(@selected_direction))} class="ml-auto lucide-chevron-down size-4 text-base-500" aria-hidden="true"></span>
    </div>
    """
  end
end
