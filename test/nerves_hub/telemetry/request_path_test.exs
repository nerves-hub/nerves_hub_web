defmodule NervesHub.Telemetry.RequestPathTest do
  # Swaps the span exporter and raises the log level, both global.
  use NervesHub.DataCase, async: false

  import ExUnit.CaptureLog

  alias NervesHub.Accounts
  alias NervesHub.Telemetry.RequestPath

  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  describe "recordable/1" do
    test "filters a token in the path" do
      conn = routed("/api/auth/cli_session/2f1b0c7e", %{"token" => "2f1b0c7e"})

      assert RequestPath.recordable(conn) == "/api/auth/cli_session/[FILTERED]"
    end

    test "keeps the rest of the path around the token" do
      conn = routed("/invite/abc123/accept", %{"token" => "abc123"})

      assert RequestPath.recordable(conn) == "/invite/[FILTERED]/accept"
    end

    test "leaves a path without a token alone, whatever its other parameters hold" do
      conn = routed("/org/token/token/devices", %{"org_name" => "token", "product_name" => "token"})

      assert RequestPath.recordable(conn) == "/org/token/token/devices"
    end

    test "leaves a path no route matched alone" do
      assert RequestPath.recordable(%{request_path: "/auth/cli/2f1b0c7e"}) == "/auth/cli/2f1b0c7e"
    end
  end

  # Requests made over HTTP, so they pass through Bandit and get a span, as in
  # production, with the span exported here and the log written the way
  # production writes it.
  describe "a CLI polling its login" do
    setup do
      original_level = Logger.level()
      Logger.configure(level: :info)
      # The SDK's own span processor, which every tracer already reports to.
      :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())

      on_exit(fn ->
        :ok = :otel_batch_processor.set_exporter(NoExporter, [])
        Logger.configure(level: original_level)
      end)
    end

    test "records neither its token in the request log nor on the trace" do
      {:ok, %{token: waiting}} = Accounts.generate_cli_session_token(nil)
      unknown = Ecto.UUID.generate()

      log =
        capture_log([format: {NervesHub.Logger, :format}, metadata: :all], fn ->
          assert poll(waiting).status == 200
          # Raises in the controller, and is rendered as a 404.
          assert poll(unknown).status == 404
        end)

      request_lines = log |> String.split("\n") |> Enum.filter(&(&1 =~ "Request completed"))

      assert length(request_lines) == 2

      for line <- request_lines do
        assert line =~ "/api/auth/cli_session/[FILTERED]"
        refute line =~ waiting
        refute line =~ unknown
      end

      assert exported_requests("/api/auth/cli_session/", 2) == [
               {"/api/auth/cli_session/[FILTERED]", 200},
               {"/api/auth/cli_session/[FILTERED]", 404}
             ]
    end
  end

  defp routed(path, path_params) do
    %{Phoenix.ConnTest.build_conn(:get, path) | path_params: path_params}
  end

  defp poll(token) do
    port = NervesHubWeb.Endpoint.config(:http)[:port]
    Req.get!("http://localhost:#{port}/api/auth/cli_session/#{token}", retry: false)
  end

  # The path and status of each request span exported under `prefix`, once
  # `count` of them have arrived. Bandit ends a request's span after it has sent
  # the response, so the client can have its answer before the span is there to
  # flush. Connections left over from other tests can make spans of their own,
  # hence the prefix.
  defp exported_requests(prefix, count, attempts \\ 20, requests \\ []) do
    :otel_tracer_provider.force_flush()
    requests = requests ++ Enum.filter(received_requests(), fn {path, _status} -> String.starts_with?(path, prefix) end)

    if length(requests) >= count or attempts == 0 do
      Enum.sort(requests)
    else
      exported_requests(prefix, count, attempts - 1, requests)
    end
  end

  defp received_requests(requests \\ []) do
    receive do
      {:span, span(attributes: attributes)} ->
        case :otel_attributes.map(attributes) do
          %{"url.path": path, "http.response.status_code": status} -> received_requests([{path, status} | requests])
          _other -> received_requests(requests)
        end
    after
      100 -> requests
    end
  end
end
