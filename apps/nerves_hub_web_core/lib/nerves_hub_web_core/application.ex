defmodule NervesHubWebCore.Application do
  use Application

  require Logger

  def start(_type, _args) do
    pubsub_config = Application.get_env(:nerves_hub_web_core, NervesHubWeb.PubSub)

    children = [
      datadog_children(),
      NervesHubWebCore.Repo,
      {Phoenix.PubSub, pubsub_config},
      {Task.Supervisor, name: NervesHubWebCore.TaskSupervisor},
      {Oban, configure_oban()},
      {NervesHubWebCore.Stats, []}
    ]

    :telemetry.attach(
      "spandex-query-tracer",
      [:nerves_hub_web_core, :repo, :query],
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

    opts = [strategy: :one_for_one, name: NervesHubWebCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def start_phase(:start_workers, _start_type, _phase_args) do
    if Application.get_env(:nerves_hub_web_core, :enable_workers) do
      # Look for all workers using the NervesHubWebCore.Worker behaviour
      # and attempt schedule_next/0 which is idempotent. So if a job
      # record already exists for the next scheduled time, then it
      # will not be duplicated.
      #
      # Jobs run recursively so we just need to ensure one is scheduled
      # at start-up. When the job runs, it will schedule its next run time.
      for module <- worker_modules() do
        worker_startup = fn ->
          # Schedule next 2 jobs
          job = module.schedule_next!()

          DateTime.diff(job.scheduled_at, DateTime.utc_now())
          |> abs()
          # right on the scheduled time
          |> Kernel.+(1)
          |> module.schedule_next!()
        end

        Task.Supervisor.start_child(
          NervesHubWebCore.TaskSupervisor,
          worker_startup,
          restart: :transient
        )
      end

      Logger.info("Workers started")
    else
      Logger.info("Workers disabled - skipping job scheduling")
    end
  end

  defp configure_oban() do
    config = Application.get_env(:nerves_hub_web_core, Oban, [])

    case Keyword.get(config, :queues, []) do
      false ->
        # queues need to be ignored if set to false
        config

      config_queues ->
        # Ensure worker defined queues are added
        worker_queues =
          for worker <- worker_modules() do
            {worker.config[:queue], worker.config[:concurrent_jobs]}
          end

        Keyword.put(config, :queues, Keyword.merge(config_queues, worker_queues))
    end
  end

  defp worker_modules() do
    for {module, _} <- :code.all_loaded(),
        behaviors = Keyword.get_values(module.module_info(:attributes), :behaviour),
        [NervesHubWebCore.Worker] in behaviors do
      module
    end
  end

  defp datadog_children do
    opts = [
      host: Application.get_env(:nerves_hub_web_core, :datadog_host, "localhost"),
      port: to_integer(Application.get_env(:nerves_hub_web_core, :datadog_port)),
      batch_size: to_integer(Application.get_env(:nerves_hub_web_core, :datadog_batch_size)),
      sync_threshold:
        to_integer(Application.get_env(:nerves_hub_web_core, :datadog_sync_threshold)),
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
