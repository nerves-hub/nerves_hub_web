defmodule NervesHubWeb.Components.Breadcrumb do
  @moduledoc """
  The breadcrumb in the top bar of a detail, new or edit page, drawn as the
  design system's top bar draws it: the list the page belongs to as a link
  (16/24 500 in `content-faint`), a 14px chevron, then the page's own item
  (16/24 600 in `content-strong`, in mono for an identifier or a version).
  An optional note follows it in mono 12/16, hidden on a phone.

  Every such page uses this rather than drawing its own, so they all match.
  """
  use Phoenix.Component

  @doc """
  Renders a breadcrumb.

  The parent link takes one of the standard navigation attributes (`navigate`,
  `patch` or `href`), forwarded to `Phoenix.Component.link/1`. Its label is
  the list's name as the sidebar gives it ("Devices", "Deployment groups").
  The last crumb is the page itself and is marked `aria-current="page"`.

  ## Examples

      <.breadcrumb navigate={~p"/org/\#{@org}/\#{@product}/devices"} root_label="Devices">
        <:crumb mono>{@device.identifier}</:crumb>
      </.breadcrumb>

      <.breadcrumb navigate={~p"/org/\#{@org}/\#{@product}/firmware"} root_label="Firmware">
        <:crumb mono>{@firmware.version}</:crumb>
        <:note>{@firmware.platform} · {@firmware.architecture}</:note>
      </.breadcrumb>

  The parent label, the crumbs and the whole breadcrumb take extra classes,
  for hiding them at some widths:

      <.breadcrumb navigate={~p"..."} root_label="Devices" root_class="sm:hidden md:block">
        <:crumb mono class="hidden lg:flex">{@device.identifier}</:crumb>
      </.breadcrumb>
  """
  attr(:root_label, :string, required: true, doc: "the name of the list the page belongs to, linking back to it")
  attr(:root_class, :string, default: nil, doc: "extra classes for the parent link, e.g. responsive visibility")
  attr(:class, :any, default: nil, doc: "extra classes for the breadcrumb")
  attr(:rest, :global, include: ~w(navigate patch href))

  slot :crumb, doc: "an item after the parent, behind a chevron; the last is the page itself" do
    attr(:mono, :boolean, doc: "set in mono, for an identifier or a version")
    attr(:class, :string, doc: "extra classes for the crumb and its chevron")
  end

  slot(:note, doc: "a mono aside after the last crumb, hidden on a phone")

  def breadcrumb(assigns) do
    assigns = assign(assigns, :last, length(assigns.crumb) - 1)

    ~H"""
    <nav aria-label="Breadcrumb" class={["flex min-w-0 items-center gap-2", @class]}>
      <.link class={["text-base font-medium whitespace-nowrap text-content-faint hover:text-content-strong", @root_class]} {@rest}>
        {@root_label}
      </.link>
      <span :for={{crumb, index} <- Enum.with_index(@crumb)} class={["flex min-w-0 items-center gap-2", crumb[:class]]}>
        <span class="lucide-chevron-right--bold size-3.5 text-content-faint" aria-hidden="true"></span>
        <span
          aria-current={if index == @last, do: "page"}
          class={["truncate text-card-title text-content-strong", crumb[:mono] && "font-mono"]}
        >
          {render_slot(crumb)}
        </span>
      </span>
      <span :for={note <- @note} class="truncate font-mono text-xs text-content-muted max-sm:hidden">{render_slot(note)}</span>
    </nav>
    """
  end
end
