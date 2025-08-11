defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHubWeb.Components.Navigation
  alias Phoenix.LiveView.JS

  defp toggle_user_menu(js \\ %JS{}), do: JS.toggle(js, to: "#user-menu")

  embed_templates("layouts/*")
end
