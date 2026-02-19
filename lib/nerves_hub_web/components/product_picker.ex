defmodule NervesHubWeb.Components.ProductPicker do
  use NervesHubWeb, :live_component

  alias NervesHub.Products

  def update(assigns, socket) do
    orgs = assigns.orgs

    banner_urls =
      for org <- orgs,
          product <- org.products,
          url = Products.banner_url(product),
          into: %{},
          do: {product.id, url}

    socket =
      socket
      |> assign(:orgs, orgs)
      |> assign(:banner_urls, banner_urls)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="product-picker" class="hidden">
      <div :for={org <- @orgs} class="p-4">
        <.link navigate={~p"/org/#{org.name}"} class="flex items-center gap-[12px]">
          <div class="org-avatar">
            {org.name |> String.split(" ") |> Enum.map(&String.first/1) |> Enum.join()}
          </div>
          <h3 class="subtitle ">{org.name}</h3>
        </.link>
        <div :if={Enum.any?(org.products)} class="-mx-4 mt-3 overflow-hidden">
          <.link
            :for={product <- org.products}
            navigate={~p"/org/#{org}/#{product}/devices"}
            class="flex items-center px-4 py-4 text-sm font-medium text-zinc-300 hover:text-neutral-50 border-b border-zinc-700 bg-cover bg-center relative overflow-hidden"
            style={@banner_urls[product.id] && "background-image: url('#{@banner_urls[product.id]}');"}
          >
            <div
              :if={@banner_urls[product.id]}
              class="absolute inset-0 bg-gradient-to-r from-zinc-900 to-zinc-900/0"
            >
            </div>
            <span class="relative">{product.name}</span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
