defmodule NervesHub.Telemetry.SentrySampler do
  @moduledoc """
  Sentry's OpenTelemetry sampler, with its decision kept where a propagator can
  send it on.

  `Sentry.OpenTelemetry.Sampler` writes whether it kept a trace into the trace
  state, as `sentry-sampled`, and a span continuing a trace inherits the decision
  from there. But for a trace it starts, it returns the trace state as a plain
  list, and OpenTelemetry only writes a `tracestate` header from one built by
  `:otel_tracestate`. So the decision never left the node. A node continuing the
  trace, such as one taking a `NervesHub.DeviceLink` call from a node holding the
  device's socket, found no `sentry-sampled` and sampled the trace again on its
  own, and the two halves of a trace were kept or dropped apart.

  This hands every decision to Sentry's sampler and builds the trace state it
  returns with `:otel_tracestate`, which Sentry's sampler reads back as well as
  its own list.
  """

  @behaviour :otel_sampler

  alias Sentry.OpenTelemetry.Sampler

  @impl :otel_sampler
  def setup(config), do: Sampler.setup(config)

  @impl :otel_sampler
  def description(config), do: Sampler.description(config)

  @impl :otel_sampler
  def should_sample(ctx, trace_id, links, span_name, span_kind, attributes, config) do
    {decision, attributes, tracestate} =
      Sampler.should_sample(ctx, trace_id, links, span_name, span_kind, attributes, config)

    {decision, attributes, tracestate(tracestate)}
  end

  defp tracestate(members) when is_list(members), do: :otel_tracestate.new(members)
  defp tracestate(tracestate), do: tracestate
end
