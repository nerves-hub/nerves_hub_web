alias NervesHubWebCore.{AuditLogs.AuditLog, Repo}
import Ecto.Query
import IO.ANSI, only: [default_color: 0, green: 0, red: 0]

Logger.configure(level: :info)

defmodule Helper do
  def convert_keys(nil), do: %{}
  def convert_keys(map) do
    map
    |> Enum.map(fn {k,v} -> {String.to_atom(k), v} end)
    |> Map.new
  end
end

{success, errors} =
  from(a in AuditLog, where: is_nil(a.description) or a.description == "")
  |> Repo.all()
  |> Enum.reduce({[], []}, fn audit_log, {success, errors} ->
    # Convert params keys from string to atom
    params = Helper.convert_keys(audit_log.params)

    # Convert changes keys from string to atom
    changes = Helper.convert_keys(audit_log.changes)

    with_description = %{audit_log | changes: changes, params: params}
                       |> AuditLog.create_description()

    AuditLog.changeset(audit_log, Map.from_struct(with_description))
    |> Repo.update()
    |> case do
      {:ok, al} ->
        IO.write("#{green()}.#{default_color()}")
        {[al | success], errors}
      {:error, al} ->
        IO.write("#{red()}.#{default_color()}")
        {success, [al | errors]}
    end
  end)

IO.puts("\nSuccess: #{green()}#{length(success)}#{default_color()}")
IO.puts("Error: #{red()}#{length(errors)}#{default_color()}")
