defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHub.Products
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

  attr(:current_scope, :any, required: true)
  slot(:inner_block, required: true)

  def page_heading(assigns) do
    assigns = assign(assigns, :banner_url, banner_url(assigns))

    ~H"""
    <div class="relative overflow-hidden">
      <div
        :if={@banner_url}
        class="absolute inset-0 bg-cover bg-center z-0"
        style={"background-image: url('#{@banner_url}');"}
      >
        <div class="absolute inset-0 bg-gradient-to-r from-base-900 to-base-900/0"></div>
      </div>
      <div class={[
        "flex items-center h-[90px] gap-4 px-6 py-7 border-b border-base-700 text-sm font-medium",
        @banner_url && "relative z-[1]"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp banner_url(%{current_scope: %{product: %Products.Product{} = product}}), do: Products.banner_url(product)

  defp banner_url(_assigns), do: nil
end
