defmodule NervesHubWWWWeb.LayoutView do
  use NervesHubWWWWeb, :view

  alias NervesHubCore.Accounts.{User, Tenant}

  def page_description(%{path_info: ["dashboard"]}) do
    "Dashboard"
  end

  def page_description(%{path_info: []}) do
    "Home"
  end

  def page_description(conn) do
    Enum.fetch!(conn.path_info, 0)
  end


  def account_data(%{assigns: %{user: %User{tenant: %Tenant{} = tenant} = user}} = conn) do
      [
        "Welcome ",
        content_tag(:a, user.name, class: "", href: "#{account_path(conn, :edit)}"),
        " [",
        content_tag(:a, tenant.name, class: "", href: "#{tenant_path(conn, :edit)}"),
        "] ",
      ]

  end

  def account_data(_conn) do
    "Hello Guest, Welcome!"
  end

  def session_buttons(%{request_path: "/dashboard"} = conn) do
    if logged_in?(conn) do
      [
        content_tag(:a, "Log Out", class: "nh_std_btn", href: "#{session_path(conn, :delete)}")
      ]
    else
      content_tag(:a, "Log In", class: "nh_std_btn", href: "#{session_path(conn, :new)}")
    end
  end

  def session_buttons(conn, _opts \\ []) do
    cond do
     logged_in?(conn) ->
      [
        content_tag(:a, "Dashboard", class: "nh_std_btn", href: "#{dashboard_path(conn, :index)}"),
        content_tag(:a, "Log Out", class: "nh_std_btn", href: "#{session_path(conn, :delete)}")
      ]
    permit_uninvited_signups?() ->
      [
        content_tag(:a, "Sign Up", class: "nh_std_btn action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{account_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}"),
        content_tag(:a, "Log In", class: "nh_std_btn action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{session_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}")
      ]
    true ->
      [
        content_tag(:a, "Log In", class: "nh_std_btn action_btn",
                                  href: "#", 
                                  "data-modal-src-url": "#{session_path(conn, :new)}",
                                  "data-success-redirect-url": "#{dashboard_path(conn, :index)}")
      ]

    end
  end



  def navigation_links(conn) do
    [
      {conn.assigns.tenant.name, tenant_path(conn, :edit)},
      {"Products", product_path(conn, :index)},
      {"All Devices", device_path(conn, :index)},
      {"Account", account_path(conn, :edit)}
    ]
  end

  def permit_uninvited_signups? do
    Application.get_env(:nerves_hub_www, NervesHubWWWWeb.AccountController)[:allow_signups]
  end

  def logged_in?(%{assigns: %{user: %User{}}}), do: true
  def logged_in?(_), do: false
end
