defmodule NervesHubWeb.Plugs.ImAlive do
  @behaviour Plug
  @moduledoc """
  A simple plug to respond to health checks.
  """

  import Plug.Conn

  def init(config), do: config

  def call(%{request_path: "/status/alive"} = conn, _) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Hello Friend!")
    |> halt
  end

  def call(conn, _), do: conn
end
