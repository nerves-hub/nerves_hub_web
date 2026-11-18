defmodule NervesHubWeb.Components.ProductSettings do
  @moduledoc """
  What a product's settings pages share: the title in the top bar and the
  tabs under it.
  """
  use NervesHubWeb, :component

  attr(:product, :map, required: true)

  @doc """
  The page title for the layout's `top_bar`, with the product's name beside it
  from `sm` up.

  On a phone the name is in the drawer's product switcher.
  """
  def title(assigns) do
    ~H"""
    <div class="flex min-w-0 items-baseline gap-3">
      <h1 class="text-base/6 font-semibold text-content-strong">Product settings</h1>
      <span class="truncate font-mono text-xs text-content-muted max-sm:hidden">{@product.name}</span>
    </div>
    """
  end

  attr(:current_scope, :map, required: true)
  attr(:tab, :atom, required: true, values: [:general, :health, :api_keys])
  attr(:profile_count, :integer, required: true)

  @doc """
  Each tab is its own LiveView, so they navigate rather than patch.
  """
  def tabs(assigns) do
    ~H"""
    <nav class="flex shrink-0 gap-6 border-b border-line-default px-6 max-sm:gap-5 max-sm:px-4" aria-label="Product settings">
      <.tab navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/settings"} selected={@tab == :general}>
        General
      </.tab>
      <.tab navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/settings/health"} selected={@tab == :health}>
        Device health
        <span class="font-mono text-xs font-normal text-content-muted">
          {@profile_count}<span class="max-sm:hidden">{if @profile_count == 1, do: " profile", else: " profiles"}</span>
        </span>
      </.tab>
      <.tab navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/settings/api_keys"} selected={@tab == :api_keys}>
        API keys
      </.tab>
    </nav>
    """
  end

  attr(:navigate, :string, required: true)
  attr(:selected, :boolean, required: true)
  slot(:inner_block, required: true)

  defp tab(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@selected && "page"}
      class={[
        "-mb-px flex h-12 items-center gap-2 border-b-2 text-sm/5 max-sm:h-11",
        if(@selected,
          do: "border-primary font-semibold text-content-strong",
          else: "border-transparent text-content-body hover:text-content-strong"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
