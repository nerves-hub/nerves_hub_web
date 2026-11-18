defmodule NervesHubWeb.Components.ProductSettings do
  @moduledoc """
  What a product's settings pages share: the title in the top bar, the tabs
  under it, and the dialog they ask in.
  """
  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

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
  attr(:api_key_count, :integer, required: true, doc: "keys that have not been deactivated")

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
        <span :if={@api_key_count > 0} class="font-mono text-xs font-normal text-content-muted">
          {@api_key_count}<span class="max-sm:hidden"> active</span>
        </span>
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

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:cancel_event, :string, default: "cancel-confirm", doc: "the event Cancel, Escape and a click outside send")

  attr(:cancel, :boolean,
    default: true,
    doc: "whether it can be cancelled: Cancel in the footer, Escape, a click outside and the close button"
  )

  slot(:inner_block, required: true)
  slot(:note, doc: "a line at the start of the footer, opposite the actions")
  slot(:actions)

  @doc """
  A modal one assign drives: the page renders it while that assign is set, and
  Cancel, Escape and a click outside all send `cancel_event` to clear it.

  General and Device health use it to ask before anything that changes every
  device or cannot be undone. API keys uses it for the create form and for the
  one-time key, which can't be cancelled: a stray click outside would throw
  the key away, so only its own button closes it.
  """
  def dialog(assigns) do
    ~H"""
    <NervesHubWeb.CoreComponents.modal
      id={@id}
      show
      on_cancel={JS.push(@cancel_event)}
      width_class="max-w-[30rem]"
      body_class=""
      dismissible={@cancel}
    >
      <%!-- Not `overflow-hidden`: a popover inside, such as the role picker, hangs past the footer. --%>
      <div class="flex flex-col">
        <div class="flex flex-col gap-3.5 px-5 pt-5 pb-4">
          <h2 id={"#{@id}-title"} class="pr-8 text-item-title text-content-strong">{@title}</h2>
          <div id={"#{@id}-description"} class="flex flex-col gap-3 text-ui/4.5 text-content-body">
            {render_slot(@inner_block)}
          </div>
        </div>
        <div class="flex items-center gap-2 rounded-b-md border-t border-line-default bg-surface-muted px-5 py-3 max-sm:flex-col-reverse max-sm:items-stretch">
          <p :if={@note != []} class="text-ui/4.5 text-content-muted">{render_slot(@note)}</p>
          <div class="ml-auto flex justify-end gap-2 max-sm:ml-0 max-sm:flex-col-reverse max-sm:*:h-11 max-sm:*:w-full">
            <.button :if={@cancel} phx-click={JS.exec("data-cancel", to: "##{@id}")}>Cancel</.button>
            {render_slot(@actions)}
          </div>
        </div>
      </div>
    </NervesHubWeb.CoreComponents.modal>
    """
  end
end
