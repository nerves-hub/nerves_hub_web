defmodule NervesHubWeb.API.UI do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:index)
  end
end
