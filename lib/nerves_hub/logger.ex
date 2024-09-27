defmodule NervesHub.Logger do
  require Logger

  @doc false
  def install() do
    handlers = %{
      [:phoenix, :endpoint, :stop] => &__MODULE__.phoenix_endpoint_stop/4
    }

    for {key, fun} <- handlers do
      :ok = :telemetry.attach({__MODULE__, key}, key, fun, :ok)
    end

    :ok
  end

  # Phoenix request logging

  @doc false
  def phoenix_endpoint_stop(_, %{duration: duration}, %{conn: conn} = metadata, _) do
    case log_level(metadata[:options][:log], conn) do
      false ->
        :ok

      level ->
        Logger.log(level, fn ->
          Logfmt.encode(
            duration: duration(duration),
            method: conn.method,
            path: request_path(conn),
            status: conn.status,
            remote_ip: formatted_ip(conn)
          )
        end)
    end
  end

  # Helper functions

  defp duration(duration) do
    duration = System.convert_time_unit(duration, :native, :microsecond)

    if duration > 1000 do
      [duration |> div(1000) |> Integer.to_string(), "ms"]
    else
      [Integer.to_string(duration), "µs"]
    end
    |> Enum.join()
  end

  defp request_path(%{request_path: request_path, query_string: query_string})
       when query_string not in ["", nil],
       do: request_path <> "?" <> query_string

  defp request_path(%{request_path: request_path}), do: request_path
  defp request_path(_), do: nil

  defp formatted_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ips] ->
        ips
        |> String.split(",")
        |> List.first()
        |> String.trim()

      _ ->
        conn.remote_ip
        |> :inet_parse.ntoa()
        |> to_string()
    end
  end

  defp log_level(nil, _conn), do: :info
  defp log_level(level, _conn) when is_atom(level), do: level
end
