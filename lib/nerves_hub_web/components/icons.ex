defmodule NervesHubWeb.Components.Icons do
  use Phoenix.Component

  # Each name draws a Lucide glyph. The values are whole class names, not
  # glyph names, because Tailwind only generates the lucide-* classes it can
  # find written out in the source. The device health icons carry their
  # status colour.
  @glyphs %{
    "add" => "lucide-plus",
    "check" => "lucide-check",
    "close" => "lucide-x",
    "connection" => "lucide-wifi",
    "download" => "lucide-file-down",
    "filter" => "lucide-funnel",
    "folder-move" => "lucide-folder-input",
    "healthy" => "lucide-circle-check text-success",
    "identify" => "lucide-locate",
    "info" => "lucide-info",
    "mute" => "lucide-bell-off",
    "open" => "lucide-external-link",
    "pinned" => "lucide-pin",
    "power" => "lucide-power",
    "save" => "lucide-save",
    "settings" => "lucide-settings",
    "trash" => "lucide-trash",
    "undo" => "lucide-rotate-ccw",
    "unhealthy" => "lucide-circle-alert text-alert",
    "unknown" => "lucide-circle-minus text-base-500",
    "unpinned" => "lucide-pin-off",
    "warning" => "lucide-triangle-alert text-warning"
  }

  @doc """
  A Lucide icon by its NervesHub name, 16px unless `class` sizes it.

  The icon is drawn in `currentColor`, so colour it with a `text-*` class or
  let it take the colour of the text around it. An icon under 16px needs the
  glyph's `--bold` weight instead (see `assets/vendor/lucideicons.js`), so use
  the `lucide-*` class directly there.

  ## Examples

      <.icon name="save" />
      <.icon name="info" class="text-content-muted" />
  """
  attr(:name, :string, required: true, values: Map.keys(@glyphs))
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  def icon(assigns) do
    assigns =
      assigns
      |> assign(:glyph, Map.fetch!(@glyphs, assigns.name))
      |> assign(:default_size, !sized?(assigns.class) && "size-4")

    ~H"""
    <span class={[@glyph, @default_size, "shrink-0", @class]} aria-hidden="true" {@rest}></span>
    """
  end

  # Two size utilities on one element are settled by stylesheet order, not
  # class order, so the default only applies when the caller sets no size.
  defp sized?(class) do
    class
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(&String.match?(&1, ~r/(^|\s)(size|w|h)-/))
  end
end
