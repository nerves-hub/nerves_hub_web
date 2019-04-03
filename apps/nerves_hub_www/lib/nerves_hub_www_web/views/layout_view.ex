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
      dashboard_path(conn, :index)
    else
      home_path(conn, :index)
    end
  end

  def has_org_role?(org, user, role) do
    Accounts.has_org_role?(org, user, role)
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
end
