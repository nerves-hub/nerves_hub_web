defmodule NervesHub.Telemetry.TracesSampler do
  @moduledoc """
  Decides what share of new traces Sentry keeps, by the kind of work that
  started them.

  Sentry's OpenTelemetry sampler calls `sample_rate/1` once per trace, for the
  span that starts it, and spans inside the trace follow that decision. So a
  rate here is a rate of whole traces, and a trace dropped here takes its
  queries with it. All the sampler knows is the span's name and the attributes
  it started with: a request is still named after its method, not its route.

  There are six kinds, each with its own rate:

    * `:requests` - requests to the web UI and API, and LiveView mounts,
      params and events, along with the async work they start
      (`NervesHub.Telemetry.AsyncTrace`). There are few of them, someone is
      waiting on each, and a slow page is only worth looking into with enough
      samples to see it. `SENTRY_REQUEST_TRACING_RATE`, `1.0` by default.
    * `:jobs` - Oban jobs. Mostly crons and rare one-off work, such as
      deleting firmware or building a delta, which a small rate would almost
      never catch. `SENTRY_JOB_TRACING_RATE`, `1.0` by default.
    * `:default` - everything else: device connections and their messages,
      deployment orchestrators, and queries and LiveView async work run
      outside any request. Device traffic dwarfs everything else, which is
      why this rate is the small one. `SENTRY_TRACING_RATE`, `0.05` by
      default.
    * `:flushes` - an analytics buffer writing a batch to ClickHouse. A busy
      buffer flushes about twice a second on every node, so these are kept at
      `SENTRY_TRACING_RATE` or 1%, whichever is lower. That is still enough to
      see how long inserts take, which nothing else reports.
    * `:reports` - what a device's extensions send all day: health and metrics
      reports, alarms, log lines and network identities, along with the health
      evaluation each health report queues. Every device sends them every few
      minutes, so they
      are kept at the same rate as flushes. Told apart by the event a span
      starts with, on the extensions channel's span or on a
      `DeviceLink.extension_message` a node holding the device's socket sent
      without a decision of its own.
    * `:none` - never kept: what `NervesHub.Telemetry.FilteredSampler` drops
      (health checks, static files, the LiveView socket, device heartbeats),
      Oban's own polling queries, and a database transaction's `begin`,
      `commit` or `rollback` that starts a trace. Dropping them here rather
      than in Sentry's inbound filters means they are never sent, and a
      heartbeat's queries are dropped along with it.

  Websocket upgrades count as `:default`, not `:requests`: the span lasts as
  long as the connection, and `/socket` is the device socket on the device
  endpoint but the console's on the web one.
  """

  alias NervesHub.Telemetry.AsyncTrace
  alias NervesHub.Telemetry.FilteredSampler
  alias OpenTelemetry.SemConv.HTTPAttributes
  alias OpenTelemetry.SemConv.Incubating.MessagingAttributes
  alias OpenTelemetry.SemConv.URLAttributes

  @type kind() :: :requests | :jobs | :default | :flushes | :reports | :none
  @type rates() :: [requests: float(), jobs: float(), default: float()]

  # The most of flushes and reports kept, whatever `SENTRY_TRACING_RATE` says.
  @max_frequent_rate 0.01

  # What a device's extensions send by themselves, every few minutes for every
  # device: `NervesHub.Extensions.Health`, `Metrics`, `Alarms`, `Logging` and
  # `NetworkIdentity`. A network identity is only sent when it changes, but one
  # whose details hold addresses that move changes on every poll.
  @report_events [
    "health:report",
    "metrics:report",
    "alarms:snapshot",
    "alarms:raised",
    "alarms:cleared",
    "logging:send",
    "network_identity:report"
  ]

  @report_spans ["Channels.ExtensionsChannel.handle_in", "DeviceLink.extension_message"]

  # Queued by each health report, and run in a trace of its own.
  @health_evaluation_span "Devices.HealthEvaluation.Queue.evaluate"

  # Oban's producers, stager, pruner and peer election, polling between jobs.
  # A job's own queries are children of its span, so they never start a trace.
  @oban_polling_queries [
    "nerves_hub.repo.query:oban_jobs",
    "nerves_hub.repo.query:oban_peers"
  ]

  # What Ecto sends to open and close a transaction. One that starts a trace is
  # from a transaction run outside any span, and is all its trace would hold:
  # the queries in between each start a trace of their own. Matched on
  # `db.statement`, which `opentelemetry_ecto` still writes rather than its
  # replacement, `db.query.text`.
  @transaction_statements ["begin", "commit", "rollback"]

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
      kind when kind in [:flushes, :reports] -> min(Keyword.fetch!(rates, :default), @max_frequent_rate)
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
      never_kept?(name, attributes) -> :none
      attributes[MessagingAttributes.messaging_system()] == :oban -> :jobs
      flush?(name) -> :flushes
      report?(name, attributes) -> :reports
      live_view?(name) or request?(attributes) -> :requests
      true -> :default
    end
  end

  defp never_kept?(name, attributes) do
    FilteredSampler.drop_trace?(name, attributes) or name in @oban_polling_queries or
      attributes[:"db.statement"] in @transaction_statements
  end

  # `opentelemetry_phoenix` names LiveView spans after the view, and the device
  # list's own refresh spans follow it. A LiveComponent's events are named after
  # the LiveView it's in, not the component, because it names them from
  # `socket.view` and a component's socket is its LiveView's.
  #
  # An async task's span is named after the view too, but one that starts a
  # trace was started outside any mount, params or event, so it isn't one.
  # Inside one, it follows the trace's decision and never reaches here.
  defp live_view?(name) when is_binary(name),
    do: String.starts_with?(name, "NervesHubWeb.Live.") and not AsyncTrace.span?(name)

  defp live_view?(_name), do: false

  defp flush?(name) when is_binary(name), do: String.starts_with?(name, "Analytics.Buffer.flush[")
  defp flush?(_name), do: false

  defp report?(@health_evaluation_span, _attributes), do: true

  defp report?(name, attributes) when name in @report_spans,
    do: attributes[:"nerves_hub.channel.event"] in @report_events

  defp report?(_name, _attributes), do: false

  defp request?(attributes) do
    path = attributes[URLAttributes.url_path()] || ""

    Map.has_key?(attributes, HTTPAttributes.http_request_method()) and
      not String.ends_with?(path, "/websocket")
  end
end
