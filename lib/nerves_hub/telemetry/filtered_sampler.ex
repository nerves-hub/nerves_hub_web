defmodule NervesHub.Telemetry.FilteredSampler do
  # Inspired by https://arathunku.com/b/2024/notes-on-adding-opentelemetry-to-an-elixir-app/

  # TODO: Add ratio sampling support

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  @behaviour :otel_sampler

  @ignored_static_paths ~r/^\/(assets|fonts|images|css)\/.*/

  @ignored_url_paths [
    "/status/alive",
    "/phoenix/live_reload/socket/websocket",
    "/live/websocket",
    "/favicon.ico",
    "/"
  ]

  @ignored_span_names [
    "Channels.DeviceSocket.heartbeat",
    "nerves_hub.repo.query:schema_migrations"
  ]

  @impl :otel_sampler
  def setup(probability \\ nil) do
    if probability do
      [ratio_sampler_config: :otel_sampler_trace_id_ratio_based.setup(probability)]
    else
      []
    end
  end

  @impl :otel_sampler
  def description(_sampler_config), do: "NervesHub.Sampler"

  @impl :otel_sampler
  def should_sample(
        ctx,
        trace_id,
        links,
        span_name,
        span_kind,
        attributes,
        sampler_config
      ) do
    result = drop_trace?(span_name, attributes)

    tracestate = Tracer.current_span_ctx(ctx) |> OpenTelemetry.Span.tracestate()

    case result do
      true ->
        {:drop, [], tracestate}

      false ->
        if config = sampler_config[:ratio_sampler_config] do
          :otel_sampler_trace_id_ratio_based.should_sample(
            ctx,
            trace_id,
            links,
            span_name,
            span_kind,
            attributes,
            config
          )
        else
          {:record_and_sample, [], tracestate}
        end
    end
  end

  def drop_trace?(span_name, attributes) do
    cond do
      Enum.member?(@ignored_span_names, span_name) ->
        true

      span_name == :GET && Enum.member?(@ignored_url_paths, attributes[:"url.path"]) ->
        true

      span_name == :GET && (attributes[:"url.path"] || "") =~ @ignored_static_paths ->
        true

      true ->
        false
    end
  end
end
