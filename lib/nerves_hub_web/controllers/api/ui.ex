defmodule NervesHubWeb.API.UI do
  use NervesHubWeb, :controller

  plug(:require_no_permission, :public_api_documentation)

  def index(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:index)
  end
end
