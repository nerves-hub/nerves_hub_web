defmodule NervesHub.Logger do
  require Logger

  @metadata_ignore_list [
    :line,
    :file,
    :domain,
    :application,
    :pid,
    :mfa,
    :time,
    :gl,
    :ansi_color,
    :__sentry__,
    :otel_trace_id,
    :otel_span_id,
    :otel_trace_flags
  ]

  def format(level, message, timestamp, metadata) do
    metadata = Keyword.drop(metadata, ignore_list())

    LogfmtEx.format(level, message, timestamp, metadata)
  end

  @doc false
  def attach() do
    events = [
      [:phoenix, :endpoint, :stop],
      [:nerves_hub, :devices, :invalid_auth],
      [:nerves_hub, :devices, :connect],
      [:nerves_hub, :devices, :disconnect],
      [:nerves_hub, :devices, :duplicate_connection],
      [:nerves_hub, :devices, :update, :automatic],
      [:nerves_hub, :devices, :update, :successful],
      [:nerves_hub, :managed_deployments, :set_deployment_group, :none_found],
      [:nerves_hub, :managed_deployments, :set_deployment_group, :one_found],
      [:nerves_hub, :managed_deployments, :set_deployment_group, :multiple_found],
      [:nerves_hub, :ssl, :fail]
    ]

    Enum.each(events, fn event ->
      :ok = :telemetry.attach({__MODULE__, event}, event, &__MODULE__.log_event/4, :ok)
    end)
  end

  # Phoenix request logging

  @doc false
  def log_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, _) do
    conn.req_headers
    |> List.keyfind("user-agent", 0)
    |> case do
      {"user-agent", "SentryUptimeBot"} ->
        # ignore User-Agent: SentryUptimeBot, its just noise
        :ok

      _ ->
        Logger.info("Request completed", %{
          duration: duration(duration),
          method: conn.method,
          path: request_path(conn),
          remote_ip: formatted_ip(conn),
          status: conn.status
        })
    end
  end

  def log_event([:nerves_hub, :devices, :invalid_auth], _, metadata, _) do
    extra =
      %{
        auth: to_string(metadata[:auth]),
        event: "nerves_hub.devices.invalid_auth",
        identifier: metadata[:device_identifier],
        org_id: metadata[:org_id],
        product_id: metadata[:product_id],
        reason: inspect(metadata[:reason]),
        shared_key: metadata[:shared_key]
      }
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    Logger.info("Device auth failed", extra)
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

  def log_event([:nerves_hub, :devices, :stale_connections], %{count: count}, _metadata, _) do
    Logger.info("Device stale connection cleaned up",
      event: "nerves_hub.devices.stale_connections",
      count: count
    )
  end

  def log_event([:nerves_hub, :devices, :disconnect], _, metadata, _) do
    Logger.info("Device disconnected",
      event: "nerves_hub.devices.disconnect",
      ref_id: metadata[:ref_id],
      identifier: metadata[:identifier]
    )
  end

  def log_event([:nerves_hub, :devices, :join_failure], _, metadata, _) do
    extra =
      %{
        channel: metadata[:channel],
        error: inspect(metadata[:error]),
        event: "nerves_hub.devices.join_failure",
        identifier: metadata[:device_identifier]
      }
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    Logger.warning("Join failure", extra)
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
    Logger.info("Device firmware updated successfully",
      event: "nerves_hub.devices.update.successful",
      identifier: metadata[:identifier],
      firmware_uuid: metadata[:firmware_uuid]
    )
  end

  def log_event([:nerves_hub, :devices, :unhandled_info], _, metadata, _) do
    extra =
      %{
        event: "nerves_hub.devices.unhandled_info",
        identifier: metadata[:device_identifier],
        msg: inspect(metadata[:msg]),
        params: inspect(metadata[:params])
      }
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    Logger.warning("Unhandled handle_info message", extra)
  end

  def log_event([:nerves_hub, :devices, :unhandled_in], _, metadata, _) do
    extra =
      %{
        event: "nerves_hub.devices.unhandled_in",
        identifier: metadata[:device_identifier],
        msg: inspect(metadata[:msg])
      }
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    Logger.warning("Unhandled handle_in message", extra)
  end

  def log_event([:nerves_hub, :managed_deployments, :set_deployment_group, :none_found], _, metadata, _) do
    Logger.info("No matching deployment groups",
      event: "nerves_hub.managed_deployments.set_deployment_group.none_found",
      identifier: metadata[:device].identifier
    )
  end

  def log_event([:nerves_hub, :managed_deployments, :set_deployment_group, :one_found], _, metadata, _) do
    Logger.info("Deployment match found",
      event: "nerves_hub.managed_deployments.set_deployment_group.one_found",
      identifier: metadata[:device].identifier,
      deployment_id: metadata[:deployment_group].id
    )
  end

  def log_event([:nerves_hub, :managed_deployments, :set_deployment_group, :multiple_found], _, metadata, _) do
    Logger.info("More than one deployment match found, setting to the first",
      event: "nerves_hub.managed_deployments.set_deployment_group.multiple_found",
      identifier: metadata[:device].identifier,
      deployment_id: metadata[:deployment_group].id
    )
  end

  def log_event([:nerves_hub, :ssl, :fail], _, metadata, _) do
    Logger.info("SSL certificate verification failed",
      event: "nerves_hub.ssl.fail",
      reason: metadata[:reason],
      cert_serial: metadata[:cert_serial],
      cert_subject: metadata[:cert_subject]
    )
  end

  @doc """
  The Erlang SSL application will log issues or failures related to verification of certificates.

  This filter is designed to ignore SSL handshake errors that occur during the `:certify` state that are not helpful or hard to understand.

  eg. TLS :server: In state :certify at ssl_handshake.erl:2201 generated SERVER ALERT: Fatal - Handshake Failure - :unknown_ca
  """
  def ssl_log_filter(log_event, _opts) do
    case log_event do
      %{
        msg:
          {:report,
           %{
             alert: {:alert, _, _, %{file: ~c"ssl_handshake.erl"}, _, _},
             role: :server,
             statename: :certify
           }}
      } ->
        :stop

      _ ->
        :ignore
    end
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

  defp request_path(%{query_string: query_string, request_path: request_path}) when query_string not in ["", nil],
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
