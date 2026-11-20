defmodule NervesHub.Telemetry.TracesSampler do
  @moduledoc """
  Decides what share of new traces Sentry keeps, by the kind of work that
  started them.

  Sentry's OpenTelemetry sampler calls `sample_rate/1` once per trace, for the
  span that starts it, and spans inside the trace follow that decision. So a
  rate here is a rate of whole traces, and a trace dropped here takes its
  queries with it. All the sampler knows is the span's name and the attributes
  it started with: a request is still named after its method, not its route.

  There are four kinds, each with its own rate:

    * `:requests` - requests to the web UI and API, and LiveView mounts,
      params and events. There are few of them, someone is waiting on each,
      and a slow page is only worth looking into with enough samples to see
      it. `SENTRY_REQUEST_TRACING_RATE`, `1.0` by default.
    * `:jobs` - Oban jobs. Mostly crons and rare one-off work, such as
      deleting firmware or building a delta, which a small rate would almost
      never catch. `SENTRY_JOB_TRACING_RATE`, `1.0` by default.
    * `:default` - everything else: device connections and their messages,
      deployment orchestrators, and queries run outside any request. Device
      traffic dwarfs everything else, which is why this rate is the small one.
      `SENTRY_TRACING_RATE`, `0.05` by default.
    * `:none` - never kept: what `NervesHub.Telemetry.FilteredSampler` drops
      (health checks, static files, the LiveView socket, device heartbeats),
      and Oban's own polling queries. Dropping them here rather than in
      Sentry's inbound filters means they are never sent, and a heartbeat's
      queries are dropped along with it.

  Websocket upgrades count as `:default`, not `:requests`: the span lasts as
  long as the connection, and `/socket` is the device socket on the device
  endpoint but the console's on the web one.
  """

  alias NervesHub.Telemetry.FilteredSampler
  alias OpenTelemetry.SemConv.HTTPAttributes
  alias OpenTelemetry.SemConv.Incubating.MessagingAttributes
  alias OpenTelemetry.SemConv.URLAttributes

  @type kind() :: :requests | :jobs | :default | :none
  @type rates() :: [requests: float(), jobs: float(), default: float()]

  # Oban's producers, stager, pruner and peer election, polling between jobs.
  # A job's own queries are children of its span, so they never start a trace.
  @oban_polling_queries [
    "nerves_hub.repo.query:oban_jobs",
    "nerves_hub.repo.query:oban_peers"
  ]

  @doc """
  The share of traces like this one to keep, for Sentry's `traces_sampler`.

  Reads the rates from `config :nerves_hub, #{inspect(__MODULE__)}`.
  """
  @spec sample_rate(SamplingContext.t()) :: float()
  def sample_rate(sampling_context) do
    sample_rate(sampling_context, Application.fetch_env!(:nerves_hub, __MODULE__))
  end

  @doc """
  The share of traces like this one to keep, given the rate for each kind.
  """
  @spec sample_rate(SamplingContext.t(), rates()) :: float()
  def sample_rate(%{transaction_context: context}, rates) do
    case kind(context.name, Map.get(context, :attributes)) do
      :none -> 0.0
      kind -> Keyword.fetch!(rates, kind)
    end
  end

  @doc """
  What kind of work a span starting a trace is, from its name and the
  attributes it started with.
  """
  @spec kind(atom() | String.t(), term()) :: kind()
  def kind(name, attributes) when not is_map(attributes), do: kind(name, %{})

  def kind(name, attributes) do
    cond do
      FilteredSampler.drop_trace?(name, attributes) -> :none
      name in @oban_polling_queries -> :none
      attributes[MessagingAttributes.messaging_system()] == :oban -> :jobs
      live_view?(name) -> :requests
      request?(attributes) -> :requests
      true -> :default
    end
  end

  # `opentelemetry_phoenix` names LiveView spans after the view, and the device
  # list's own refresh spans follow it. A LiveComponent's events are named after
  # the LiveView it's in, not the component, because it names them from
  # `socket.view` and a component's socket is its LiveView's.
  defp live_view?(name) when is_binary(name), do: String.starts_with?(name, "NervesHubWeb.Live.")
  defp live_view?(_name), do: false

  defp request?(attributes) do
    path = attributes[URLAttributes.url_path()] || ""

    Map.has_key?(attributes, HTTPAttributes.http_request_method()) and
      not String.ends_with?(path, "/websocket")
  end
end
