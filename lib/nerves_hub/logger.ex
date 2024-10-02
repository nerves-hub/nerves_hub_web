defmodule NervesHub.Logger do
  require Logger

  @metadata_ignore_list [:line, :file, :domain, :application, :pid, :mfa]
  @pattern Logger.Formatter.compile(
             " ts=\"$date $time\" level=$level msg=\"$message\" $metadata\n"
           )

  def format(level, message, timestamp, metadata) do
    metadata = Keyword.drop(metadata, ignore_list())

    message =
      if is_binary(message) do
        String.replace(message, "\"", "'")
      else
        message
      end

    Logger.Formatter.format(@pattern, level, message, timestamp, metadata)
  end

  @doc false
  def attach() do
    events = [
      [:phoenix, :endpoint, :stop],
      [:nerves_hub, :devices, :connect],
      [:nerves_hub, :devices, :disconnect],
      [:nerves_hub, :devices, :duplicate_connection],
      [:nerves_hub, :devices, :update, :automatic]
    ]

    Enum.each(events, fn event ->
      :ok = :telemetry.attach({__MODULE__, event}, event, &__MODULE__.log_event/4, :ok)
    end)
  end

  # Phoenix request logging

  @doc false
  def log_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, _) do
    Logger.info("Request completed", %{
      duration: duration(duration),
      method: conn.method,
      path: request_path(conn),
      status: conn.status,
      remote_ip: formatted_ip(conn)
    })
  end

  def log_event([:nerves_hub, :devices, :connect], _, metadata, _) do
    Logger.info("Device connected",
      event: "nerves_hub.devices.connect",
      ref_id: metadata[:ref_id],
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

  defp ignore_list() do
    if Application.get_env(:nerves_hub, :log_include_mfa) do
      @metadata_ignore_list -- [:mfa]
    else
      @metadata_ignore_list
    end
  end

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
end
