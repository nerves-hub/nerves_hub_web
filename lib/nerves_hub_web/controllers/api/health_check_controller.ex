defmodule NervesHubWeb.API.HealthCheckController do
  @moduledoc "A health check for the app"

  use NervesHubWeb, :api_controller

  require Logger

  @doc """
  Just return a 200 response.

  We could expand this to include a test query to the database.
  """
  def health_check(conn, _),
    do: json(conn, %{status: "UP"})

  def node_check(conn, _) do
    sync_nodes =
      System.get_env("SYNC_NODES_OPTIONAL", "")
      |> String.split(" ")
      |> Enum.reject(& &1 == "")
      |> Enum.map(&String.to_atom/1)
      |> Enum.into(%{}, fn node ->
        {node, Node.connect(node)}
      end)

    Logger.info("Reconnected nodes - #{inspect(sync_nodes)}")

    json(conn, %{status: "CONNECTED"})
  end
end
