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
        <span class="lucide-arrow-left size-4 text-content-muted" aria-hidden="true"></span>
        <span class={["text-content-muted", @root_class]}>{@root_label}</span>
      </.link>
      <span :for={crumb <- @crumb} class="contents">
        <span class={["text-content-muted", crumb[:class]]}>/</span>
        <span class={["font-semibold text-content-strong", crumb[:class]]}>{render_slot(crumb)}</span>
      </span>
    </div>
    """
  end
end
