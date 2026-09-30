defmodule NervesHubWeb.ScriptRunController do
  @moduledoc """
  Downloads for a bulk script run.

  A controller rather than the run's LiveView: a download is a plain GET returning a
  file, and the results are streamed straight to the socket rather than held in
  memory — a run can be tens of thousands of devices wide, each with its own output.
  """

  use NervesHubWeb, :controller

  alias NervesHub.ScriptRunners
  alias NimbleCSV.RFC4180, as: CSV

  plug(:validate_role, org: :view)

  @doc """
  A run's device results as a CSV.

  The file is named for the moment it was taken, because a run in progress exports
  differently a minute later and the operator ends up with several of these.
  """
  def export(%{assigns: %{current_scope: scope}} = conn, %{"script_run_id" => id}) do
    run = ScriptRunners.get_by_id!(scope, id)

    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{export_filename(run)}"])
      |> send_chunked(:ok)

    {:ok, conn} = chunk(conn, CSV.dump_to_iodata([ScriptRunners.export_csv_header()]))

    {:ok, conn} =
      ScriptRunners.export_reducer(run, conn, fn conn, line ->
        chunk(conn, CSV.dump_to_iodata([line]))
      end)

    conn
  end

  # The run's name plus the timestamp of the export. UTC, and punctuation a file
  # system is happy with.
  defp export_filename(run) do
    taken_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%Y-%m-%d_%H%M%S")

    "#{slug(run.name)}-#{taken_at}.csv"
  end

  # A run's name is whatever the operator typed, which can hold anything.
  defp slug(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]+/, "-")
    |> String.trim("-")
    |> String.downcase()
    |> case do
      "" -> "script-run"
      slug -> slug
    end
  end
end
