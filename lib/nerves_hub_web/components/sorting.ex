defmodule NervesHubWeb.Components.Sorting do
  use NervesHubWeb, :component

  attr(:field, :any)
  attr(:text, :any)
  attr(:selected_field, :any)
  attr(:selected_direction, :any)

  def sort_icon(assigns) do
    ~H"""
    <div class="flex items-center group">
      {@text}
      <svg :if={@selected_field != @field} class="ml-auto invisible group-hover:visible w-6 h-6" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12.5 7.5L10 5L7.5 7.5M12.5 12.5L10 15L7.5 12.5" stroke="#71717A" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
      <svg :if={@selected_field == @field && (@selected_direction == "asc" || is_nil(@selected_direction))} class="ml-auto w-5 h-5" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M17 14L12 9L7 14" stroke="#71717A" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
      <svg :if={@selected_field == @field && @selected_direction == "desc"} class="ml-auto w-5 h-5" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M17 10L12 15L7 10" stroke="#71717A" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </div>
    """
  end
end
