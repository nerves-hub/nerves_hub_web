defmodule NervesHub.Logger do
  require Logger

  @doc false
  def install() do
    handlers = %{
      [:phoenix, :endpoint, :stop] => &__MODULE__.log_event/4,
      [:nerves_hub, :devices, :connect] => &__MODULE__.log_event/4,
      [:nerves_hub, :devices, :disconnect] => &__MODULE__.log_event/4,
      [:nerves_hub, :devices, :duplicate_connection] => &__MODULE__.log_event/4,
      [:nerves_hub, :devices, :update, :automatic] => &__MODULE__.log_event/4
    }

    for {key, fun} <- handlers do
      :ok = :telemetry.attach({__MODULE__, key}, key, fun, :ok)
    end

    :ok
  end

  # Phoenix request logging

  @doc false
  def log_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn} = metadata, _) do
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

  def log_event([:nerves_hub, :devices, :connect], _, metadata, _) do
    Logger.info("Device connected",
      event: "nerves_hub.devices.connect",
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end

  def log_event([:nerves_hub, :devices, :duplicate_connection], _, metadata, _) do
    Logger.info("Device duplicate connection detected",
      event: "nerves_hub.devices.duplicate_connection",
      ref_id: metadata[:ref_id],
      identifier: metadata[:device].identifier
    )
  end

  def log_event([:nerves_hub, :devices, :disconnect], _, metadata, _) do
    Logger.info("Device disconnected",
      event: "nerves_hub.devices.disconnect",
      ref_id: metadata[:ref_id],
      identifier: metadata[:identifier]
    )
  end

  def log_event([:nerves_hub, :devices, :update, :automatic], _, metadata, _) do
    Logger.info("Device received update",
      event: "nerves_hub.devices.update.automatic",
      ref_id: metadata[:ref_id],
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end

  def log_event([:nerves_hub, :devices, :update, :successful], _, metadata, _) do
    Logger.info("Device updated firmware",
      event: "nerves_hub.devices.update.successful",
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
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
