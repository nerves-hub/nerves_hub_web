defmodule NervesHub.Supervisor do
  use Supervisor

  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :undefined)
  end

  def init(:undefined) do
    pubsub_config = Application.get_env(:nerves_hub_www, NervesHub.PubSub)

    children = [
      datadog_children(),
      NervesHub.Repo,
      {Phoenix.PubSub, pubsub_config},
      {Task.Supervisor, name: NervesHub.TaskSupervisor},
      {Oban, configure_oban()},
      {NervesHub.Stats, []}
    ]

    :telemetry.attach(
      "spandex-query-tracer",
      [:nerves_hub_www, :repo, :query],
      &SpandexEcto.TelemetryAdapter.handle_event/4,
      nil
    )

    SpandexPhoenix.Telemetry.install(
      customize_metadata: fn conn ->
        service = Map.get(conn.private, :service, :elixir)

        conn
        |> SpandexPhoenix.default_metadata()
        |> Keyword.put(:service, service)
      end
    )

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.init(children, opts)
  end

  defp configure_oban() do
    Application.get_env(:nerves_hub_www, Oban, [])
  end

  defp datadog_children() do
    opts = [
      host: Application.get_env(:nerves_hub_www, :datadog_host, "localhost"),
      port: to_integer(Application.get_env(:nerves_hub_www, :datadog_port)),
      batch_size: to_integer(Application.get_env(:nerves_hub_www, :datadog_batch_size)),
      sync_threshold: to_integer(Application.get_env(:nerves_hub_www, :datadog_sync_threshold)),
      http: HTTPoison
    ]

    {SpandexDatadog.ApiServer, opts}
  end

  defp to_integer(_string, _error_value \\ nil)

  defp to_integer(not_a_string, _error_value) when is_integer(not_a_string),
    do: not_a_string

  defp to_integer(string, error_value) when is_binary(string) do
    string
    |> Float.parse()
    |> case do
      {float_value, _remainder} -> round(float_value)
      :error -> error_value
    end
  end

  defp to_integer(_, error_value), do: error_value
end
