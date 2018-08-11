defmodule NervesHubWWWWeb.LayoutView do
  use NervesHubWWWWeb, :view

  alias NervesHubCore.Accounts.{Org, User, Tenant}

  def page_description(%{path_info: ["dashboard"]}) do
    "Dashboard"
  end

  def page_description(%{path_info: []}) do
    "Home"
  end

  def page_description(conn) do
    Enum.fetch!(conn.path_info, 0)
  end


  def account_data(%{assigns: %{user: %User{org: %Org{} = org} = user}} = conn) do
      [
        "Welcome ",
        content_tag(:a, user.name, class: "", href: "#{account_path(conn, :edit)}"),
        " [",
        content_tag(:a, org.name, class: "", href: "#{org_path(conn, :edit, org)}"),
        "] ",
      ]

  end

  def account_data(_conn) do
    "Hello Guest, Welcome!"
  end

  def session_buttons(%{request_path: "/dashboard"} = conn) do
    if logged_in?(conn) do
      [
        content_tag(:a, "Log Out", class: "btn btn-outline-danger ml-3", href: "#{session_path(conn, :delete)}")
      ]
    else
      content_tag(:a, "Log In", class: "btn btn-outline-primary ml-3", href: "#{session_path(conn, :new)}")
    end
  end

  def session_buttons(conn, _opts \\ []) do
    cond do
     logged_in?(conn) ->
      [
        content_tag(:a, "Dashboard", class: "btn btn-outline-primary ml-3", href: "#{dashboard_path(conn, :index)}"),
        content_tag(:a, "Log Out", class: "btn btn-outline-primary ml-3", href: "#{session_path(conn, :delete)}")
      ]
    permit_uninvited_signups?() ->
      [
        content_tag(:a, "Create Account", class: "btn btn-outline-primary ml-3 action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{account_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}"),
        content_tag(:a, "Log In", class: "btn btn-outline-success ml-3 action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{session_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}")
      ]
    true ->
      [
        content_tag(:a, "Log In", class: "btn btn-outline-success ml-3 action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{session_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}")
      ]

    end
  end



  def navigation_links(conn) do
    [
      {"Dashboard", dashboard_path(conn, :index)},
      {"Products", product_path(conn, :index)},
      {"All Devices", device_path(conn, :index)}
    ]
  end

  def permit_uninvited_signups? do
    Application.get_env(:nerves_hub_www, NervesHubWWWWeb.AccountController)[:allow_signups]
  end

  def logged_in?(%{assigns: %{user: %User{}}}), do: true
  def logged_in?(_), do: false

  def permit_uninvited_signups do
    Application.get_env(:nerves_hub_www, NervesHubWWWWeb.AccountController)[:allow_signups]
  end
end
