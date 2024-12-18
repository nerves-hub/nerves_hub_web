defmodule NervesHubWeb.Plugs.ImAlive do
  @behaviour Plug
  @moduledoc """
  A simple plug to respond to health checks.
  """

  import Plug.Conn

  def init(config), do: config

  def call(%{request_path: "/status/alive"} = conn, _) do
    case Ecto.Adapters.SQL.query(NervesHub.Repo, "SELECT true", []) do
      {:ok, _} -> send_result(conn, 200, "Hello, Friend!")
      _result -> send_result(conn, 500, "Sorry, Friend :(")
    end
  end

  def call(conn, _), do: conn

  defp send_result(conn, code, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(code, message)
    |> halt
  end
end
