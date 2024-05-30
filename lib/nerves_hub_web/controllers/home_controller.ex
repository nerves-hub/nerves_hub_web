defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        case conn.assigns[:orgs] do
          # Single org, redirect
          [org] ->
            redirect(conn, to: Routes.product_path(conn, :index, org.name))

          orgs when is_list(orgs) ->
            # Redirect to last selected org if the user has made a selection in the past
            if conn.assigns[:latest_org] &&
                 Enum.any?(orgs, &(&1.name == conn.assigns[:latest_org])) do
              redirect(conn, to: Routes.product_path(conn, :index, conn.assigns[:latest_org]))
            else
              render(conn, "index.html")
            end

          # Otherwise, just do the listing
          _ ->
            render(conn, "index.html")
        end

      false ->
        redirect(conn, to: Routes.session_path(conn, :new))
    end
  end

  def error(_conn, _params) do
    raise "Error"
  end

  def online_devices(conn, _params) do
    render(conn, "online_devices.html", devices: [])
  end
end
