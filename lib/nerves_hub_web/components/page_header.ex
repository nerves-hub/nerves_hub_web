defmodule NervesHubWeb.Components.PageHeader do
  @moduledoc """
  Two flavours of page header that appear at the top of the right-hand
  content column underneath the action strip.

    * `simple/1`  — title on the left with optional `:inner_block` content
      beside it and optional right-aligned `:actions`. Used by every list
      and create/edit form.
    * `detail/1`  — leading status indicator + title with inline meta on
      the left, info-pills / buttons on the right. Used by the show pages
      (device, deployment group, firmware, archive).

  Both accept:

    * `banner_url` — optional background image. Adds a horizontal gradient
      overlay on the left so the title stays legible regardless of the
      photo.
    * `fade_bottom` — opt-in vertical gradient that fades the banner into
      the page background. Use on pages where tabs (no `border-b`) sit
      immediately below the header.
    * `border` — controls the `border-b` (`true` by default on `simple`,
      `false` by default on `detail`).
  """

  use NervesHubWeb, :html

  attr(:title, :string, default: nil)
  attr(:banner_url, :string, default: nil)
  attr(:fade_bottom, :boolean, default: false)
  attr(:border, :boolean, default: true)
  attr(:size, :atom, default: :large, values: [:large, :small])
  attr(:class, :string, default: nil)
  slot(:inner_block, doc: "additional content next to the title (badges, search, etc.)")
  slot(:actions, doc: "right-aligned actions")

  def simple(assigns) do
    ~H"""
    <div
      class={[
        "relative flex h-[90px] shrink-0 items-center gap-4 overflow-hidden px-6 py-7",
        @border && "border-base-700 border-b",
        @banner_url && "bg-cover bg-center",
        @class
      ]}
      style={@banner_url && "background-image: url('#{@banner_url}');"}
    >
      <.gradients banner_url={@banner_url} fade_bottom={@fade_bottom} />
      <div class="relative flex flex-1 items-center gap-4 text-sm font-medium">
        <h1
          :if={@title}
          class={[
            "text-base-50 font-semibold",
            @size == :large && "text-xl leading-[30px]",
            @size == :small && "text-base"
          ]}
        >
          {@title}
        </h1>
        {render_slot(@inner_block)}
      </div>
      <div :if={@actions != []} class="relative flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr(:banner_url, :string, default: nil)
  attr(:fade_bottom, :boolean, default: false)
  attr(:border, :boolean, default: false)
  attr(:class, :string, default: nil)
  slot(:status, doc: "leading status indicator (typically a colored dot)")
  slot(:title, required: true, doc: "title content; may include inline badges")
  slot(:actions, doc: "right-aligned info pills / buttons")

  def detail(assigns) do
    ~H"""
    <div
      class={[
        "relative flex h-[90px] shrink-0 justify-between gap-2 overflow-hidden p-6",
        @border && "border-base-700 border-b",
        @banner_url && "bg-cover bg-center",
        @class
      ]}
      style={@banner_url && "background-image: url('#{@banner_url}');"}
    >
      <.gradients banner_url={@banner_url} fade_bottom={@fade_bottom} />
      <div class="relative flex items-center gap-3">
        {render_slot(@status)}
        {render_slot(@title)}
      </div>
      <div :if={@actions != []} class="relative flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr(:banner_url, :string, default: nil)
  attr(:fade_bottom, :boolean, default: false)

  defp gradients(assigns) do
    ~H"""
    <div
      :if={@banner_url}
      class="from-base-900 to-base-900/0 via-base-900/50 absolute inset-0 bg-linear-to-r via-20% to-45%"
    >
    </div>
    <div
      :if={@banner_url && @fade_bottom}
      class="from-surface to-surface/0 absolute inset-0 bg-linear-to-t"
    >
    </div>
    """
  end
end
