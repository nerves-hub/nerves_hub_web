defmodule NervesHubWeb.Components.ProductPicker do
  use NervesHubWeb, :live_component

  alias NervesHubWeb.Layouts

  def update(assigns, socket) do
    {:ok, assign(socket, :orgs, assigns.orgs)}
  end

  def render(assigns) do
    ~H"""
    <div id="product-picker" class="w-[264px] absolute top-0 left-[265px] hidden">
      <div class="fixed top-0 left-[265px] w-full h-full bg-surface/70 z-30"></div>
      <div class="relative">
        <div
          class="relative p-3 border-r border-b border-base-700 bg-surface-muted z-50 max-h-[612px] overflow-y-scroll overscroll-none scrollbar-thin scrollbar-thumb-base-800 scrollbar-track-base-900"
          phx-window-keydown={Layouts.hide_product_picker()}
          phx-key="escape"
          phx-click-away={Layouts.toggle_product_picker()}
        >
          <div :for={org <- @orgs} class="flex flex-col gap-2 p-4">
            <.link navigate={~p"/org/#{org.name}"} class="flex items-center gap-3 group">
              <div class="org-avatar">
                {org.name |> String.split(" ") |> Enum.map(&String.first/1) |> Enum.join()}
              </div>
              <h3 class="subtitle underline-base underline-left underline-color-indigo-500 group-hover:underline-expanded">{org.name}</h3>
            </.link>
            <div class="flex flex-col gap-1.5">
              <div :for={product <- org.products}>
                <.link navigate={~p"/org/#{org}/#{product}/devices"} class="product-picker-product">
                  {product.name}
                </.link>
              </div>
            </div>
          </div>
        </div>
        <div class="absolute -inset-0.5 rounded-md translate-x-1 translate-y-1 blur-sm bg-gradient-to-br from-alert via-success to-primary z-40"></div>
      </div>
    </div>
    """
  end
end
