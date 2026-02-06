defmodule NervesHubWeb.Plugs.ImAlive do
  @moduledoc """
  A simple plug to respond to health checks.
  """

  @behaviour Plug

  import Plug.Conn

  alias Ecto.Adapters.SQL

  @status_path "/status/alive"
  def init(config), do: config

  def call(%{request_path: @status_path} = conn, _) do
    case SQL.query(NervesHub.Repo, "SELECT true", []) do
      {:ok, _} -> send_result(conn, 200, "Hello, Friend!")
      _result -> send_result(conn, 500, "Sorry, Friend :(")
    end
  end

  def call(conn, _), do: conn

  def status_path_spec() do
    %{
      @status_path => %OpenApiSpex.PathItem{
        get: %OpenApiSpex.Operation{
          summary: "Check application status",
          description:
            "Provides a simple health check to verify that the application is running, responsive, and can connect to the database.",
          tags: ["Status"],
          operationId: "Status.alive",
          responses: %{
            "200" => %OpenApiSpex.Response{
              description: "The application is running and the database is reachable.",
              content: %{
                "text/plain" => %OpenApiSpex.MediaType{
                  schema: %OpenApiSpex.Schema{type: :string, example: "Hello, Friend!"}
                }
              }
            },
            "500" => %OpenApiSpex.Response{
              description: "The application is running but the database is unreachable.",
              content: %{
                "text/plain" => %OpenApiSpex.MediaType{
                  schema: %OpenApiSpex.Schema{type: :string, example: "Sorry, Friend :("}
                }
              }
            }
          },
          # This endpoint does not require authentication, so we override the global security
          security: []
        }
      }
    }
  end

  defp send_result(conn, code, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(code, message)
    |> halt()
  end
end
