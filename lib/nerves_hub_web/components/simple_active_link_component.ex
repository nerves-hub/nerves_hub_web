defmodule NervesHubWeb.Components.SimpleActiveLink do
  use NervesHubWeb, :component

  def simple_active_link(assigns) do
    is_active = assigns.href == ~r/^#{assigns.current_path}/

    classes =
      if is_active do
        assigns.class <> " active"
      else
        assigns.class
      end

    assigns = Map.put(assigns, :class, classes)

    ~H"""
    <.link href={@href} class={@class}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end
end
