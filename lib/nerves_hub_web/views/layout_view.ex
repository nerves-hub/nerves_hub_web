defmodule NervesHubWeb.LayoutView do
  use NervesHubWeb, :view
  use Timex

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Products.Product
  alias Timex.Format.Duration.Formatter, as: TimexFormatter

  def product(%{assigns: %{product: %Product{} = product}}) do
    product
  end

  def product(_conn) do
    nil
  end

  def device_count(%{assigns: %{org: %{id: org_id}}}) do
    Devices.get_device_count_by_org_id(org_id)
  end

  def device_count(_conn) do
    nil
  end

  def logged_in?(%{assigns: %{user: %User{}}}), do: true

  def logged_in?(_), do: false

  def has_org_role?(org, user, role) do
    Accounts.has_org_role?(org, user, role)
  end

  def help_icon(message, placement \\ :top) do
    content_tag(:i, "",
      class: "help-icon far fa-question-circle",
      data: [toggle: "help-tooltip", placement: placement],
      title: message
    )
  end

  @tib :math.pow(2, 40)
  @gib :math.pow(2, 30)
  @mib :math.pow(2, 20)
  @kib :math.pow(2, 10)
  @precision 3

  def humanize_seconds(seconds) do
    seconds
    |> Timex.Duration.from_seconds()
    |> TimexFormatter.format(:humanized)
  end

  @doc """
  Note that results are in multiples of unit bytes: KiB, MiB, GiB
  [Wikipedia](https://en.wikipedia.org/wiki/Binary_prefix)
  """
  def humanize_size(bytes) do
    cond do
      bytes > @tib -> "#{Float.round(bytes / @gib, @precision)} TiB"
      bytes > @gib -> "#{Float.round(bytes / @gib, @precision)} GiB"
      bytes > @mib -> "#{Float.round(bytes / @mib, @precision)} MiB"
      bytes > @kib -> "#{Float.round(bytes / @kib, @precision)} KiB"
      true -> "#{bytes} bytes"
    end
  end

  @doc """
  Creates a series of pagination links to use with a Phoenix.LiveView page.

  When one of the links is clicked, it sends a `"paginate"` event with the
  expected page number for the LiveView to handle.

  Requires a map with `:total_pages` key or `:total_records` and `:page_size`
  keys to calculate `:total_pages` for you.

  Likewise, you can supply your list of records and applicable options (such
  as `:page_size`) to `pagination_links/2` which will calculate `:total_pages`
  for you.
  """
  def pagination_links(%{total_pages: _, links: true} = opts) do
    opts = Map.put_new(opts, :page_number, 1)

    anchor = if opts.anchor, do: "##{opts.anchor}", else: ""

    distance = 8
    start_range = round(max(1, opts.page_number - distance / 2))
    end_range = min(round(start_range + distance), opts.total_pages)

    assigns =
      Map.merge(opts, %{
        start_range: start_range,
        end_range: end_range,
        distance: distance,
        anchor: anchor
      })

    ~H"""
    <div class="btn-group btn-group-toggle btn-group-gap">
      <div :if={@page_number > 1}>
        {link("&lt;&lt;",
          to: "?page=#{@page_number - 1}#{@anchor}",
          class: "btn btn-secondary btn-sm"
        )}
      </div>
      <div :for={page <- @start_range..@end_range}>
        {link("#{page}",
          to: "?page=#{page}#{@anchor}",
          class: "btn btn-secondary btn-sm #{if page == @page_number, do: "active"}"
        )}
      </div>
      <div :if={@total_pages > @distance}>
        <span class="btn btn-secondary btn-sm">…</span>
      </div>
      <div :if={@page_number < @total_pages}>
        {link("&gt;&gt;",
          to: "?page=#{@page_number + 1}#{@anchor}",
          class: "btn btn-secondary btn-sm"
        )}
      </div>
    </div>
    """
  end

  def pagination_links(%{total_pages: _} = opts) do
    opts = Map.put_new(opts, :page_number, 1)

    distance = 8
    start_range = round(max(1, opts.page_number - distance / 2))
    end_range = min(round(start_range + distance), opts.total_pages)

    assigns =
      Map.merge(opts, %{start_range: start_range, end_range: end_range, distance: distance})

    ~H"""
    <div :if={@total_pages > 0} class="btn-group btn-group-toggle btn-group-gap">
      <div :if={@start_range > 1}>
        <button class="btn btn-secondary btn-sm" phx-click="paginate" phx-value-page="1">1</button>
      </div>
      <div :if={@start_range > 2}>
        <button class="btn btn-secondary btn-sm" phx-click="paginate" phx-value-page="…">…</button>
      </div>
      <div :for={page <- @start_range..@end_range}>
        <button phx-click="paginate" phx-value-page={page} class={"btn btn-secondary btn-sm #{if page == @page_number do "active" end}"}>
          {page}
        </button>
      </div>
      <%= if @total_pages > @distance do %>
        <div>
          <button class="btn btn-secondary btn-sm" phx-click="paginate" phx-value-page="…">…</button>
        </div>
        <div>
          <button class="btn btn-secondary btn-sm" phx-click="paginate" phx-value-page={@total_pages}>{@total_pages}</button>
        </div>
      <% end %>
      <div :if={@page_number > 1}>
        <button class="btn btn-secondary btn-sm " phx-click="paginate" phx-value-page={@page_number - 1}>&lt;&lt;</button>
      </div>
      <div :if={@page_number < @total_pages}>
        <button class="btn btn-secondary btn-sm " phx-click="paginate" phx-value-page={@page_number + 1}>&gt;&gt;</button>
      </div>
    </div>
    """
  end

  def pagination_links(%{total_records: record_count, page_size: size} = opts) do
    opts
    |> Map.put(:total_pages, ceil(record_count / size))
    |> pagination_links()
  end

  def reworked_pager(opts) do
    opts = Map.put_new(opts, :page_number, 1)

    distance = 8
    start_range = round(max(1, opts.page_number - distance / 2))
    end_range = min(round(start_range + distance), opts.total_pages)

    assigns =
      Map.merge(opts, %{start_range: start_range, end_range: end_range, distance: distance})

    ~H"""
    <div :if={@total_pages > 1} class="flex gap-4">
      <button class="pager-button" disabled={@page_number < 2} phx-click="paginate" phx-value-page={@page_number - 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M11.6667 5.83337L7.5 10L11.6667 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
      <button :for={page <- @start_range..@end_range} phx-click="paginate" phx-value-page={page} class={"pager-button #{if page == @page_number do "active-page" end}"}>
        {page}
      </button>
      <button :if={@total_pages > @distance} class="pager-button" phx-click="paginate" phx-value-page="…">…</button>
      <button :if={@end_range != @total_pages} class="pager-button" phx-click="paginate" phx-value-page={@total_pages}>{@total_pages}</button>
      <button class={["pager-button", @page_number == @total_pages && "invisible"]} phx-click="paginate" phx-value-page={@page_number + 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M8.3335 5.83337L12.5002 10L8.3335 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
    </div>
    """
  end

  def sidebar_links(%{path_info: ["account" | _tail]} = conn), do: sidebar_account(conn)

  def sidebar_links(%{path_info: ["org", "new"]}), do: []

  def sidebar_links(%{path_info: ["org", _org_name | _tail]} = conn), do: sidebar_org(conn)

  def sidebar_links(_conn), do: []

  def sidebar_org(conn) do
    [
      # %{title: "Dashboard", icon: "tachometer-alt", active: "", href: Routes.product_path(conn, :show, conn.assigns.org.name, conn.assigns.product.name)},
      %{
        title: "Devices",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/devices"
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/firmware"
      },
      %{
        title: "Archives",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/archives"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/deployment_groups"
      },
      %{
        title: "Scripts",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/scripts"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/org/#{conn.assigns.org}/#{conn.assigns.product}/settings"
      }
    ]
    |> sidebar_active(conn)
  end

  def sidebar_account(conn) do
    [
      %{
        title: "Personal Info",
        active: "",
        href: ~p"/account"
      },
      %{
        title: "Access Tokens",
        active: "",
        href: ~p"/account/tokens"
      }
    ]
    |> sidebar_active(conn)
  end

  def sidebar_active(links, %{request_path: request_path}) do
    Enum.map(links, fn link ->
      if link.href == request_path do
        %{link | active: "active"}
      else
        link
      end
    end)
  end

  def org_classes(conn, org_name) do
    case conn.path_info do
      ["org", ^org_name | _] ->
        "active"

      _ ->
        "dropdown-toggle"
    end
  end

  defmodule DateTimeFormat do
    def from_now(timestamp) do
      if Timex.is_valid?(timestamp) do
        Timex.from_now(timestamp)
      else
        timestamp
      end
    end
  end
end
