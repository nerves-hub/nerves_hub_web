defmodule BeamwareWeb.DashboardController do
  use BeamwareWeb, :controller

  def index(conn, _params) do
    conn
    |> render "index.html"
  end
end
