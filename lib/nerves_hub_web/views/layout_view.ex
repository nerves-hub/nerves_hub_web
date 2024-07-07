defmodule NervesHubWeb.LayoutView do
  use NervesHubWeb, :view
  use Timex

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Products.Product

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
    |> Timex.Format.Duration.Formatter.format(:humanized)
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

    content_tag(:div, class: "btn-group btn-group-toggle") do
      opts
      |> Scrivener.HTML.raw_pagination_links(distance: Map.get(opts, :distance, 8))
      |> Enum.map(fn {text, page} ->
        if text == :ellipsis do
          content_tag(:span, page, class: "btn btn-secondary btn-sm")
        else
          link(text,
            to: "?page=#{page}#{anchor}",
            class: "btn btn-secondary btn-sm #{if page == opts.page_number, do: "active"}"
          )
        end
      end)
    end
  end

  def pagination_links(%{total_pages: _} = opts) do
    opts = Map.put_new(opts, :page_number, 1)

    content_tag(:div, class: "btn-group btn-group-toggle") do
      opts
      |> Scrivener.HTML.raw_pagination_links(distance: Map.get(opts, :distance, 8))
      |> Enum.map(fn {text, page} ->
        text = if text == :ellipsis, do: page, else: text

        content_tag(:div) do
          content_tag(:button, text,
            phx_click: "paginate",
            phx_value_page: page,
            class: "btn btn-secondary btn-sm #{if page == opts.page_number, do: "active"}"
          )
        end
      end)
    end
  end

  def pagination_links(%{total_records: record_count, page_size: size} = opts) do
    opts
    |> Map.put(:total_pages, ceil(record_count / size))
    |> pagination_links()
  end

  def sidebar_links(%{path_info: ["account" | _tail]} = conn),
    do: sidebar_account(conn)

  def sidebar_links(%{path_info: ["org", "new"]}),
    do: []

  def sidebar_links(%{path_info: ["org", _org_name | _tail]} = conn),
    do: sidebar_org(conn)

  def sidebar_links(_conn), do: []

  def sidebar_org(conn) do
    [
      # %{title: "Dashboard", icon: "tachometer-alt", active: "", href: Routes.product_path(conn, :show, conn.assigns.org.name, conn.assigns.product.name)},
      %{
        title: "Devices",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/devices"
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/firmware"
      },
      %{
        title: "Archives",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/archives"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/deployments"
      },
      %{
        title: "Scripts",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/scripts"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/products/#{hashid(conn.assigns.product)}/settings"
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
