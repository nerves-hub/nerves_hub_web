defmodule NervesHub.Telemetry.SentrySamplerTest do
  # Not async: Sentry reads its `traces_sampler` from global config, which these
  # tests change.
  use ExUnit.Case, async: false

  alias NervesHub.Telemetry.SentrySampler
  alias OpenTelemetry.Tracer
  alias Sentry.OpenTelemetry.Sampler

  require Record

  Record.defrecordp(:span_ctx, Record.extract(:span_ctx, from_lib: "opentelemetry_api/include/opentelemetry.hrl"))

  setup do
    previous = Sentry.Config.traces_sampler()
    on_exit(fn -> Sentry.put_config(:traces_sampler, previous) end)
  end

  describe "a trace it starts" do
    test "sends on the decision to keep it" do
      keep(1.0)

      assert {:record_and_sample, [], tracestate} = start_trace(SentrySampler)
      assert :otel_tracestate.get("sentry-sampled", tracestate) == "true"
      assert sent_headers(tracestate, 1)["tracestate"] =~ "sentry-sampled=true"
    end

    test "sends on the decision to drop it" do
      keep(0.0)

      assert {:drop, [], tracestate} = start_trace(SentrySampler)
      assert sent_headers(tracestate, 0)["tracestate"] =~ "sentry-sampled=false"
    end

    # Pins the reason this module exists. If this fails, Sentry's sampler builds
    # its trace state properly, and `SentrySampler` can go.
    test "is needed, because Sentry's sampler alone sends no decision" do
      keep(1.0)

      assert {:record_and_sample, [], tracestate} = start_trace(Sampler)
      refute Map.has_key?(sent_headers(tracestate, 1), "tracestate")
    end
  end

  describe "a trace continued from another node" do
    test "is kept when the other node kept it, whatever the rate here" do
      keep(1.0)
      {:record_and_sample, [], tracestate} = start_trace(SentrySampler)
      headers = sent_headers(tracestate, 1)

      keep(0.0)
      assert {:record_and_sample, [], _tracestate} = continue_trace(headers)
    end

    test "is dropped when the other node dropped it, whatever the rate here" do
      keep(0.0)
      {:drop, [], tracestate} = start_trace(SentrySampler)
      headers = sent_headers(tracestate, 0)

      keep(1.0)
      assert {:drop, [], _tracestate} = continue_trace(headers)
    end
  end

  defp keep(rate), do: Sentry.put_config(:traces_sampler, fn _sampling_context -> rate end)

  defp start_trace(sampler) do
    sampler.should_sample(:otel_ctx.new(), random_id(128), [], "Channels.DeviceChannel.handle_in", :internal, %{}, [])
  end

  defp continue_trace(headers) do
    ctx = :otel_propagator_text_map.extract_to(:otel_ctx.new(), Enum.to_list(headers))
    SentrySampler.should_sample(ctx, random_id(128), [], "DeviceLink.device_message", :server, %{}, [])
  end

  # The headers a span holding this trace state sends to the next node, through
  # the propagators this node is configured with.
  defp sent_headers(tracestate, trace_flags) do
    span_ctx =
      span_ctx(
        trace_id: random_id(128),
        span_id: random_id(64),
        trace_flags: trace_flags,
        tracestate: tracestate,
        is_valid: true,
        is_recording: trace_flags == 1
      )

    :otel_ctx.new()
    |> Tracer.set_current_span(span_ctx)
    |> :otel_propagator_text_map.inject_from([])
    |> Map.new()
  end

  defp random_id(bits), do: :rand.uniform(2 ** bits - 1)
end
