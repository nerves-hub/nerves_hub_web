defmodule NervesHub.StatsdMetricsReporterTest do
  use ExUnit.Case, async: true

  alias NervesHub.StatsdMetricsReporter

  describe "metrics/0" do
    test "returns a non-empty list of telemetry metrics" do
      metrics = StatsdMetricsReporter.metrics()
      assert is_list(metrics)
      refute Enum.empty?(metrics)
    end

    test "all entries are Telemetry.Metrics structs" do
      for metric <- StatsdMetricsReporter.metrics() do
        assert is_struct(metric)
      end
    end

    test "includes device connect counter" do
      names = Enum.map(StatsdMetricsReporter.metrics(), & &1.name)
      assert [:nerves_hub, :devices, :connect, :count] in names
    end

    test "includes device disconnect counter" do
      names = Enum.map(StatsdMetricsReporter.metrics(), & &1.name)
      assert [:nerves_hub, :devices, :disconnect, :count] in names
    end
  end

  describe "config/0" do
    test "returns empty list when no statsd host is configured" do
      original = Application.get_env(:nerves_hub, :statsd, [])
      Application.put_env(:nerves_hub, :statsd, [])
      on_exit(fn -> Application.put_env(:nerves_hub, :statsd, original) end)

      assert StatsdMetricsReporter.config() == []
    end

    test "returns a child spec list when statsd host is configured" do
      original = Application.get_env(:nerves_hub, :statsd, [])
      Application.put_env(:nerves_hub, :statsd, host: "statsd.example.com", port: 8125)
      on_exit(fn -> Application.put_env(:nerves_hub, :statsd, original) end)

      config = StatsdMetricsReporter.config()
      assert [_spec] = config
      assert {TelemetryMetricsStatsd, opts} = hd(config)
      assert opts[:host] == "statsd.example.com"
      assert opts[:port] == 8125
    end
  end
end
