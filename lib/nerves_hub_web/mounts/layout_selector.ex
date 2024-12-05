defmodule NervesHubWeb.Mounts.LayoutSelector do
  import Phoenix.Component

  def on_mount(layout, _, session, socket) do
    if Application.get_env(:nerves_hub, :new_ui) && session["new_ui"] do
      {:cont, assign(socket, :new_ui, true), layout: {NervesHubWeb.Layouts, layout}}
    else
      {:cont, socket, layout: {NervesHubWeb.LayoutView, :live}}
    end
  end
end
