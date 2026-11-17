defmodule NervesHub.Workers.RequeueStrandedScriptRunnersTest do
  @moduledoc """
  The cron job that rescues a run whose pacer was lost.

  A run's pacer is inserted once, when the run is created. If that job is
  discarded -- five failed attempts, or a `Lifeline` rescue of an
  attempt-exhausted job -- nothing else would ever insert another, and the run
  would never finish. Worse, it keeps counting towards
  `NervesHub.ScriptRunners.active_run_count/0`, so every later run divides the
  ceiling by a run that is never going to finish.
  """
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.Workers.RequeueStrandedScriptRunners
  alias NervesHub.Workers.ScriptRunnerDispatch

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{user: user, org: org, product: product, firmware: firmware}
  end

  defp create_run(ctx) do
    tag = "requeue-#{System.unique_integer([:positive])}"
    Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, %{tags: [tag]})

    {:ok, runner, []} =
      ScriptRunners.create(ctx.product, ctx.user, %{
        name: "Say hi #{tag}",
        text: "IO.puts(:hi)",
        filter_type: :tags,
        filter: %{tags: [tag], tag_operator: :or}
      })

    runner
  end

  defp dispatch_jobs_for(runner) do
    all_enqueued(worker: ScriptRunnerDispatch)
    |> Enum.filter(&(&1.args["script_runner_id"] == runner.id))
  end

  # Stands in for a pacer that exhausted its attempts.
  #
  # `scheduled_at` is backdated along with the state. This repo carries a unique
  # index on `oban_jobs (args, scheduled_at, worker)`, and Postgres freezes
  # `now()` for the length of a transaction -- which, under the Ecto sandbox, is
  # the whole test. Without this the replacement insert would collide with the
  # discarded row on a timestamp that only matches because the test never
  # committed.
  defp discard_pacer(runner) do
    Repo.update_all(
      from(j in "oban_jobs",
        where: j.worker == "NervesHub.Workers.ScriptRunnerDispatch",
        where: fragment("(? ->> 'script_runner_id')::bigint = ?", j.args, ^runner.id)
      ),
      set: [state: "discarded", scheduled_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :minute)]
    )

    assert dispatch_jobs_for(runner) == []
  end

  test "runs cleanly when nothing is stranded" do
    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})
  end

  test "gives a new pacer to a run that lost its own", ctx do
    runner = create_run(ctx)
    discard_pacer(runner)

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})

    assert [_job] = dispatch_jobs_for(runner)
  end

  # The new pacer is a working one: it dispatches the run's devices and, once
  # they answer, finishes the run, which frees its slice of the ceiling.
  test "the new pacer works the run through to the end", ctx do
    runner = create_run(ctx)
    discard_pacer(runner)

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})
    [job] = dispatch_jobs_for(runner)

    assert {:snooze, _} = perform_job(ScriptRunnerDispatch, job.args)

    for result <- ScriptRunners.device_results(runner) do
      _ = ScriptRunners.record_device_result(runner.id, result.device_id, :completed, "done")
    end

    assert :ok = perform_job(ScriptRunnerDispatch, job.args)
    assert Repo.get!(ScriptRunner, runner.id).status == :completed
  end

  test "leaves a run that still has a pacer alone", ctx do
    runner = create_run(ctx)

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})

    assert [_only_one] = dispatch_jobs_for(runner)
  end

  test "a completed run is not given a pacer it has no use for", ctx do
    runner = create_run(ctx)
    discard_pacer(runner)
    {:ok, _} = ScriptRunners.mark_finished(runner)

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})

    assert dispatch_jobs_for(runner) == []
  end
end
