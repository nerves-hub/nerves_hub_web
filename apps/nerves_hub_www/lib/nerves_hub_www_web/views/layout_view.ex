defmodule NervesHubWWWWeb.LayoutView do
  use NervesHubWWWWeb, :view

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.User

  def navigation_links(%{assigns: %{current_org: org, user: user}} = conn) do
    if has_org_role?(org, user, :read) do
      [
        {"Products", product_path(conn, :index)},
        {"All Devices", device_path(conn, :index)}
      ]
    else
      [
        {"Products", product_path(conn, :index)}
      ]
    end
  end

  def user_orgs(%{assigns: %{user: %User{} = user}}) do
    Accounts.get_user_orgs_with_product_role(user, :read)
  end

  def user_orgs(_conn), do: []

  def logged_in?(%{assigns: %{user: %User{}}}), do: true
  def logged_in?(_), do: false

  def logo_href(conn) do
    if logged_in?(conn) do
      product_path(conn, :index)
    else
      home_path(conn, :index)
    end
  end

  def has_org_role?(org, user, role) do
    Accounts.has_org_role?(org, user, role)
  end

  def health_status_icon(%{healthy: healthy?}) do
    {icon, color} = if healthy?, do: {"check-circle", "green"}, else: {"times-circle", "red"}
    content_tag(:i, "", class: "fas fa-#{icon}", style: "color:#{color}")
  end

  def health_status_icon(_) do
    content_tag(:i, "",
      class: "fas fa-question-circle",
      title: "Don't know how to tell health status"
    )
  end

  def help_icon(message, placement \\ :top) do
    content_tag(:i, "",
      class: "help-icon far fa-question-circle",
      data: [toggle: "help-tooltip", placement: placement],
      title: message
    )
  end

  def permit_uninvited_signups do
    Application.get_env(:nerves_hub_www, NervesHubWWWWeb.AccountController)[:allow_signups]
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
  def pagination_links(%{total_pages: _} = opts) do
    opts = Map.put_new(opts, :page_number, 1)

    content_tag(:div, class: "btn-group btn-group-toggle", data: [toggle: "buttons"]) do
      opts
      |> Scrivener.HTML.raw_pagination_links(distance: opts[:distance] || 8)
      |> Enum.map(fn {text, page} ->
        text = if text == :ellipsis, do: page, else: text

        content_tag(:button, text,
          phx_click: "paginate",
          phx_value: page,
          class: "btn btn-secondary btn-sm #{if page == opts.page_number, do: "active"}"
        )
      end)
    end
  end

  def pagination_links(%{total_records: record_count, page_size: size} = opts) do
    opts
    |> Map.put(:total_pages, ceil(record_count / size))
    |> pagination_links()
  end

  @doc """
  Like `pagination_links/1` but allows you to send a list which will be used
  to deduce `:total_pages` required to generate the links.
  """
  def pagination_links(records, opts \\ []) when is_list(records) do
    Map.new(opts)
    |> Map.put(:total_records, length(records))
    |> Map.put_new(:page_size, 20)
    |> pagination_links()
  end
end
