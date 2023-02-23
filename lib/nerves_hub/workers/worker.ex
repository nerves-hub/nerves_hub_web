defmodule NervesHub.Worker do
  @moduledoc """
  Behaviour required for creating scheduled worker jobs.

  This references the `Oban.Worker` behaviour and requires a `perform/2`
  function to satisfy it's requirements.

  The allowed configuration options are:
  * `:schedule` - required `%Crontab.CronExpression{}` or string
  equivilent (`"*/2 * * * *"`)
  * `:queue` - string or atom representing the queue. Defaults to `__MODULE__`
  * `:args` - map of arguments to be used when scheduling a job for
  this worker. Defaults to `%{}`
  * `concurrent_jobs` - integer representing how many jobs can run concurrently
  * All other `Oban.Job.option()` are supported
  ```
  def MyModule do
    use NervesHub.Worker,
      queue: :my_queue,
      schedule: "*/2 * * * *",
      args: %{arg1: "test"}
  ```

  Using this behaviour will create a `schedule_next!/0` function in
  the calling module which will schedule a job for the next available
  time according to the `:schedule` key with the provided `:args`.
  Jobs are unique by `:args` and `:scheduled_at` keys in the database,
  so calling `schedule_next!/0` whill return the existing job if it
  was previously scheduled.

  The first time a job attempts to run, it will schedule out the next
  job based on the `:schedule` key, essentially creating a recursive
  loop.

  To enable workers behaviour, add it to your
  config:
  ```
  config :nerves_hub_www, :enable_workers, true
  ```

  During startup, a start_phase will check workers are enabled and
  find all modules using this behaviour then call `schedule_next!/0`.
  This will ensure there is always a scheduled job to start the loop.
  """
  @callback run(Oban.Job.t()) :: any()
  @callback schedule_next!() :: Oban.Job.t() | no_return()

  alias Crontab.CronExpression, as: Cron
  alias Crontab.CronExpression.Parser, as: CronParser

  defmacro __using__(config) do
    config =
      format_schedule!(config)
      |> Keyword.put_new(:concurrent_jobs, 1)
      |> Keyword.put_new(:queue, __CALLER__.module)

    oban_opts = Keyword.drop(config, [:args, :concurrent_jobs, :schedule])

    quote location: :keep do
      @behaviour NervesHub.Worker

      use Oban.Worker, unquote(oban_opts)

      def config(), do: unquote(config)

      def perform(%{attempt: 1} = job) do
        # Recursively schedule out the next job
        schedule_next!()

        run(job)
      end

      def perform(job), do: run(job)

      def schedule_next!(time_offset \\ 1) do
        args = config()[:args] || %{}

        # offset the time by at least one second in the future to
        # ensure we're actually getting the next run time and
        # not repeating the same date
        offset = NaiveDateTime.utc_now() |> NaiveDateTime.add(time_offset, :second)

        next_date = Crontab.Scheduler.get_next_run_date!(config()[:schedule], offset)

        new(args, scheduled_at: next_date)
        |> Oban.insert!()
      end
    end
  end

  defp format_schedule!(config) do
    schedule =
      case Keyword.get(config, :schedule) do
        %Cron{} = schedule ->
          schedule

        schedule when is_binary(schedule) ->
          CronParser.parse!(schedule)

        _ ->
          raise ArgumentError,
                "NervesHub.Worker use must have a valid cron expression.\n\t\"*/5 * * * *\"\n\t~e[*/5 * * * *]"
      end
      |> Macro.escape()

    Keyword.put(config, :schedule, schedule)
  end
end
