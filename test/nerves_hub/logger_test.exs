defmodule NervesHub.LoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias NervesHub.Logger, as: NHLogger

  setup do
    original_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: original_level) end)
    :ok
  end

  # ---- format/4 ----

  describe "format/4" do
    test "strips metadata_ignore_list keys and delegates to LogfmtEx" do
      metadata = [
        line: 42,
        file: "foo.ex",
        domain: [:elixir],
        application: :nerves_hub,
        pid: self(),
        mfa: {Foo, :bar, 0},
        time: 0,
        gl: self(),
        ansi_color: "\e[32m",
        __sentry__: %{},
        otel_trace_id: "abc",
        otel_span_id: "def",
        otel_trace_flags: "01",
        custom_key: "preserved"
      ]

      output = NHLogger.format(:info, "test message", {{2025, 1, 1}, {0, 0, 0, 0}}, metadata)

      result = IO.iodata_to_binary(output)
      assert String.contains?(result, "custom_key")
      refute String.contains?(result, "otel_trace_id")
      refute String.contains?(result, "application")
    end
  end

  # ---- log_event/4 — phoenix endpoint stop ----

  describe "log_event [:phoenix, :endpoint, :stop]" do
    test "logs request info for normal user agents" do
      conn = %Plug.Conn{
        req_headers: [{"user-agent", "Mozilla/5.0"}],
        method: "GET",
        request_path: "/devices",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1}
      }

      log =
        capture_log(fn ->
          NHLogger.log_event([:phoenix, :endpoint, :stop], %{duration: 1_000_000}, %{conn: conn}, :ok)
        end)

      assert log =~ "Request completed"
    end

    test "ignores SentryUptimeBot user agent" do
      conn = %Plug.Conn{
        req_headers: [{"user-agent", "SentryUptimeBot"}],
        method: "GET",
        request_path: "/health",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1}
      }

      log =
        capture_log(fn ->
          NHLogger.log_event([:phoenix, :endpoint, :stop], %{duration: 500}, %{conn: conn}, :ok)
        end)

      refute log =~ "Request completed"
    end

    test "logs request info with query string without crashing" do
      conn = %Plug.Conn{
        req_headers: [],
        method: "GET",
        request_path: "/devices",
        query_string: "page=2&per=10",
        status: 200,
        remote_ip: {127, 0, 0, 1}
      }

      log =
        capture_log(fn ->
          NHLogger.log_event([:phoenix, :endpoint, :stop], %{duration: 500}, %{conn: conn}, :ok)
        end)

      assert log =~ "Request completed"
    end

    test "logs request info with x-forwarded-for header without crashing" do
      conn = %Plug.Conn{
        req_headers: [{"x-forwarded-for", "1.2.3.4, 5.6.7.8"}],
        method: "POST",
        request_path: "/api/device",
        query_string: "",
        status: 201,
        remote_ip: {10, 0, 0, 1}
      }

      log =
        capture_log(fn ->
          NHLogger.log_event([:phoenix, :endpoint, :stop], %{duration: 500}, %{conn: conn}, :ok)
        end)

      assert log =~ "Request completed"
    end

    test "formats duration without crashing for any native time value" do
      conn = %Plug.Conn{
        req_headers: [],
        method: "GET",
        request_path: "/",
        query_string: "",
        status: 200,
        remote_ip: {127, 0, 0, 1}
      }

      native_2ms = System.convert_time_unit(2, :millisecond, :native)

      log =
        capture_log(fn ->
          NHLogger.log_event([:phoenix, :endpoint, :stop], %{duration: native_2ms}, %{conn: conn}, :ok)
        end)

      assert log =~ "Request completed"
    end
  end

  # ---- log_event/4 — device events ----

  describe "log_event [:nerves_hub, :devices, :invalid_auth]" do
    test "logs Device auth failed" do
      metadata = [auth: :cert, reason: :unknown_ca, org_id: 1, device_identifier: "dev-001"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :invalid_auth], %{}, metadata, :ok)
        end)

      assert log =~ "Device auth failed"
    end
  end

  describe "log_event [:nerves_hub, :devices, :connect]" do
    test "logs Device connected" do
      metadata = [ref_id: "ref-1", identifier: "dev-abc", firmware_uuid: "fw-uuid"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :connect], %{}, metadata, :ok)
        end)

      assert log =~ "Device connected"
    end
  end

  describe "log_event [:nerves_hub, :devices, :connecting_code_failure]" do
    test "logs Connecting code failure" do
      metadata = [output: "some error output", identifier: "dev-fail"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :connecting_code_failure], %{}, metadata, :ok)
        end)

      assert log =~ "Connecting code failure"
    end
  end

  describe "log_event [:nerves_hub, :devices, :disconnect]" do
    test "logs Device disconnected" do
      metadata = [ref_id: "ref-2", device_id: 42, device_identifier: "dev-xyz"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :disconnect], %{}, metadata, :ok)
        end)

      assert log =~ "Device disconnected"
    end
  end

  describe "log_event [:nerves_hub, :devices, :duplicate_connection]" do
    test "logs Device duplicate connection detected" do
      metadata = [ref_id: "ref-3", device_id: 99, device_identifier: "dev-dup"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :duplicate_connection], %{}, metadata, :ok)
        end)

      assert log =~ "duplicate connection"
    end
  end

  describe "log_event [:nerves_hub, :devices, :update, :automatic]" do
    test "logs Device received update" do
      metadata = [ref_id: "ref-4", identifier: "dev-upd", firmware_uuid: "fw-new"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :update, :automatic], %{}, metadata, :ok)
        end)

      assert log =~ "Device received update"
    end
  end

  describe "log_event [:nerves_hub, :devices, :update, :successful]" do
    test "logs Device firmware updated successfully" do
      metadata = [identifier: "dev-ok", firmware_uuid: "fw-done"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :update, :successful], %{}, metadata, :ok)
        end)

      assert log =~ "firmware updated successfully"
    end
  end

  describe "log_event [:nerves_hub, :devices, :network_interface_mismatch]" do
    test "logs Network interface mismatch warning" do
      metadata = [params: %{interface: "eth0"}]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :network_interface_mismatch], %{}, metadata, :ok)
        end)

      assert log =~ "Network interface mismatch"
    end
  end

  describe "log_event [:nerves_hub, :devices, :downloader_network_interface_nil]" do
    test "logs nil downloader network interface warning" do
      metadata = [params: %{interface: nil}]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :devices, :downloader_network_interface_nil], %{}, metadata, :ok)
        end)

      assert log =~ "nil downloader network interface"
    end
  end

  # ---- managed_deployments events ----

  describe "log_event [:nerves_hub, :managed_deployments, :set_deployment_group, :none_found]" do
    test "logs No matching deployment groups" do
      device = %{identifier: "dev-none"}
      metadata = [device: device]

      log =
        capture_log(fn ->
          NHLogger.log_event(
            [:nerves_hub, :managed_deployments, :set_deployment_group, :none_found],
            %{},
            metadata,
            :ok
          )
        end)

      assert log =~ "No matching deployment groups"
    end
  end

  describe "log_event [:nerves_hub, :managed_deployments, :set_deployment_group, :one_found]" do
    test "logs Deployment match found" do
      device = %{identifier: "dev-one"}
      deployment_group = %{id: 7}
      metadata = [device: device, deployment_group: deployment_group]

      log =
        capture_log(fn ->
          NHLogger.log_event(
            [:nerves_hub, :managed_deployments, :set_deployment_group, :one_found],
            %{},
            metadata,
            :ok
          )
        end)

      assert log =~ "Deployment match found"
    end
  end

  describe "log_event [:nerves_hub, :managed_deployments, :set_deployment_group, :multiple_found]" do
    test "logs More than one deployment match found" do
      device = %{identifier: "dev-multi"}
      deployment_group = %{id: 3}
      metadata = [device: device, deployment_group: deployment_group]

      log =
        capture_log(fn ->
          NHLogger.log_event(
            [:nerves_hub, :managed_deployments, :set_deployment_group, :multiple_found],
            %{},
            metadata,
            :ok
          )
        end)

      assert log =~ "More than one deployment match found"
    end
  end

  describe "log_event [:nerves_hub, :ssl, :fail]" do
    test "logs SSL certificate verification failed" do
      metadata = [reason: :unknown_ca, cert_serial: "1234", cert_subject: "CN=device"]

      log =
        capture_log(fn ->
          NHLogger.log_event([:nerves_hub, :ssl, :fail], %{}, metadata, :ok)
        end)

      assert log =~ "SSL certificate verification failed"
    end
  end

  # ---- ssl_log_filter/2 ----

  describe "ssl_log_filter/2" do
    test "stops SSL certify handshake failure events" do
      log_event = %{
        msg:
          {:report,
           %{
             alert: {:alert, :fatal, :handshake_failure, %{file: ~c"ssl_handshake.erl"}, :none, :none},
             role: :server,
             statename: :certify
           }}
      }

      assert NHLogger.ssl_log_filter(log_event, []) == :stop
    end

    test "ignores non-matching log events" do
      log_event = %{msg: {:string, "some other SSL message"}}

      assert NHLogger.ssl_log_filter(log_event, []) == :ignore
    end

    test "ignores SSL alerts from non-certify state" do
      log_event = %{
        msg:
          {:report,
           %{
             alert: {:alert, :fatal, :handshake_failure, %{file: ~c"ssl_handshake.erl"}, :none, :none},
             role: :server,
             statename: :connection
           }}
      }

      assert NHLogger.ssl_log_filter(log_event, []) == :ignore
    end
  end
end
