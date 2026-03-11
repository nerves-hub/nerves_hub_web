defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHubWeb.Components.Navigation
  alias Phoenix.LiveView.JS

  defp toggle_user_menu(js \\ %JS{}), do: JS.toggle(js, to: "#user-menu")

  embed_templates("layouts/*")

  def toggle_product_picker(js \\ %JS{}) do
    JS.toggle(js,
      to: "#product-picker",
      in: {"ease-in duration-200", "opacity-0", "opacity-100"},
      out: {"ease-out duration-200", "opacity-100", "opacity-0"}
    )
  end

  def hide_product_picker(js \\ %JS{}) do
    JS.hide(js,
      to: "#product-picker",
      transition: {"ease-out duration-200", "opacity-100", "opacity-0"}
    )
  end
end
