defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHubWeb.Components.Navigation
  alias Phoenix.LiveView.JS

  defp toggle_user_menu(js \\ %JS{}) do
    js
    |> JS.toggle(to: "#user-menu")
  end

  embed_templates("layouts/*")
end
