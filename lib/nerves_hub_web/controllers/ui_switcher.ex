defmodule NervesHubWeb.UiSwitcherController do
  use NervesHubWeb, :controller

  def index(conn, params) do
    return_to = params["return_to"] || ~p"/orgs"

    new_ui = get_session(conn)["new_ui"] || false

    conn
    |> put_session("new_ui", !new_ui)
    |> redirect(to: return_to)
  end
end
