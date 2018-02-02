defmodule BeamwareWeb.PageController do
  use BeamwareWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
