defmodule NervesHub.Telemetry.TracesSamplerTest do
  use ExUnit.Case, async: true

  alias NervesHub.Telemetry.TracesSampler

  @rates [requests: 1.0, jobs: 0.5, default: 0.05]

  # What Sentry's sampler hands `traces_sampler`: the name and the attributes
  # the span started with.
  defp sampling_context(name, attributes) do
    %SamplingContext{
      transaction_context: %{name: name, op: name, trace_id: 1, attributes: attributes},
      parent_sampled: nil
    }
  end

  defp request(path, method \\ :GET) do
    {method, %{"http.request.method": method, "url.path": path}}
  end

  describe "kind/2" do
    test "web UI and API requests are requests" do
      for {name, attributes} <- [
            request("/org/acme/widgets/devices"),
            request("/api/orgs/acme/products/widgets/firmwares"),
            request("/api/orgs/acme/products/widgets/devices/abc/code", :POST)
          ] do
        assert TracesSampler.kind(name, attributes) == :requests
      end
    end

    test "LiveView mounts, params and events are requests" do
      for name <- [
            "NervesHubWeb.Live.Devices.Show.mount",
            "NervesHubWeb.Live.Devices.Show.handle_params",
            "NervesHubWeb.Live.Devices.Index.handle_event#select",
            "NervesHubWeb.Live.Devices.Index.refresh_device_list"
          ] do
        assert TracesSampler.kind(name, %{}) == :requests
      end
    end

    test "websocket upgrades are not requests" do
      for path <- ["/socket/websocket", "/device-socket/websocket", "/events-socket/websocket"] do
        {name, attributes} = request(path)
        assert TracesSampler.kind(name, attributes) == :default
      end
    end

    test "Oban jobs are jobs" do
      attributes = %{"messaging.system": :oban, "messaging.destination.name": "default"}

      assert TracesSampler.kind("NervesHub.Workers.DeleteFirmware.process", attributes) == :jobs
    end

    test "device traffic, orchestrators and stray queries are default" do
      for name <- [
            "Channels.ExtensionsChannel.handle_in",
            "Channels.DeviceSocket.on_connect",
            "ManagedDeployments.Distributed.Orchestrator.trigger_update",
            "nerves_hub.repo.query:device_alarms"
          ] do
        assert TracesSampler.kind(name, %{}) == :default
      end
    end

    test "health checks, static files and the LiveView socket are never kept" do
      for path <- ["/status/alive", "/assets/js/app.js", "/fonts/inter.woff2", "/live/websocket", "/"] do
        {name, attributes} = request(path)
        assert TracesSampler.kind(name, attributes) == :none
      end
    end

    test "device heartbeats are never kept" do
      assert TracesSampler.kind("Channels.DeviceSocket.heartbeat", %{}) == :none
    end

    test "Oban's polling queries are never kept" do
      for name <- ["nerves_hub.repo.query:oban_jobs", "nerves_hub.repo.query:oban_peers"] do
        assert TracesSampler.kind(name, %{}) == :none
      end
    end

    test "a transaction's begin, commit or rollback is never kept when it starts a trace" do
      for statement <- ["begin", "commit", "rollback"] do
        assert TracesSampler.kind("nerves_hub.repo.query", %{"db.statement": statement}) == :none
      end
    end

    test "any other query that starts a trace is default" do
      for statement <- ["SELECT pg_try_advisory_xact_lock($1)", "INSERT INTO \"begin\" VALUES ($1)"] do
        assert TracesSampler.kind("nerves_hub.repo.query", %{"db.statement": statement}) == :default
      end
    end

    test "an analytics buffer's flush is a flush" do
      assert TracesSampler.kind("Analytics.Buffer.flush[device_log_lines]", %{}) == :flushes
    end

    test "a span that started without attributes is still classified" do
      assert TracesSampler.kind("Channels.DeviceChannel.join", :undefined) == :default
      assert TracesSampler.kind(:GET, nil) == :default
    end
  end

  describe "sample_rate/2" do
    test "returns the rate for the kind" do
      {name, attributes} = request("/org/acme")
      assert TracesSampler.sample_rate(sampling_context(name, attributes), @rates) == 1.0

      job = sampling_context("NervesHub.Workers.SendEmail.process", %{"messaging.system": :oban})
      assert TracesSampler.sample_rate(job, @rates) == 0.5

      message = sampling_context("Channels.ExtensionsChannel.handle_in", %{})
      assert TracesSampler.sample_rate(message, @rates) == 0.05
    end

    test "keeps flushes at the default rate, but never more than 1%" do
      flush = sampling_context("Analytics.Buffer.flush[device_messages]", %{})

      assert TracesSampler.sample_rate(flush, @rates) == 0.01
      assert TracesSampler.sample_rate(flush, Keyword.put(@rates, :default, 0.001)) == 0.001
    end

    test "returns 0.0 for what is never kept, whatever the rates" do
      {name, attributes} = request("/status/alive")
      rates = [requests: 1.0, jobs: 1.0, default: 1.0]

      assert TracesSampler.sample_rate(sampling_context(name, attributes), rates) == 0.0
    end
  end
end
