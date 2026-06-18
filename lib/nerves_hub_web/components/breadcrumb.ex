defmodule NervesHubWeb.Components.Breadcrumb do
  @moduledoc """
  The breadcrumb trail shown at the top of detail, new, and edit pages.

  It renders a back-link to the parent listing (a left arrow followed by a root
  label) and then one or more `/`-separated crumbs.
  """
  use Phoenix.Component

  @doc """
  Renders a breadcrumb trail.

  The link target is supplied via one of the standard navigation attributes
  (`navigate`, `patch`, or `href`); they are forwarded to `Phoenix.Component.link/1`.

  ## Examples

      <.breadcrumb navigate={~p"/org/\#{@org}/\#{@product}/devices"} root_label="All Devices">
        <:crumb>{@device.identifier}</:crumb>
      </.breadcrumb>

  Crumbs (and the root label) accept extra classes, which is useful for
  responsive visibility:

      <.breadcrumb navigate={~p"..."} root_label="All Devices" root_class="hidden whitespace-nowrap md:block">
        <:crumb class="hidden lg:block">{@device.identifier}</:crumb>
      </.breadcrumb>
  """
  attr(:root_label, :string, required: true, doc: "label for the back-link to the parent listing")
  attr(:root_class, :string, default: nil, doc: "extra classes for the root label, e.g. responsive visibility")
  attr(:class, :string, default: nil, doc: "extra classes for the breadcrumb wrapper")
  attr(:rest, :global, include: ~w(navigate patch href))

  slot :crumb, doc: "a trailing crumb, rendered after a `/` separator" do
    attr(:class, :string, doc: "extra classes applied to the crumb and its leading separator")
  end

  def breadcrumb(assigns) do
    ~H"""
    <div class={["flex items-center gap-2.5", @class]}>
      <.link class="back-link flex items-center gap-2.5" {@rest}>
        <svg
          class="stroke-base-400"
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 20 20"
          fill="none"
        >
          <path
            d="M4.16671 10L9.16671 5M4.16671 10L9.16671 15M4.16671 10H15.8334"
            stroke-width="1.2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <span class={["text-base-400", @root_class]}>{@root_label}</span>
      </.link>
      <span :for={crumb <- @crumb} class="contents">
        <span class={["text-base-400", crumb[:class]]}>/</span>
        <span class={["text-base-50 font-semibold", crumb[:class]]}>{render_slot(crumb)}</span>
      </span>
    </div>
    """
  end
end
