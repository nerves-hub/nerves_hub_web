defmodule NervesHub.Workers.RequeueStrandedScriptRunnersTest do
  @moduledoc """
  The cron job that rescues a run whose pacer was lost.

  What it does is covered in `NervesHub.ScriptRunners.requeue_stranded_runs/0`'s
  own tests; what is asserted here is that the worker is wired to it and reports a
  clean result either way.
  """
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
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
        name: "Say hi",
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

  test "runs cleanly when nothing is stranded" do
    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})
  end

  test "gives a new pacer to a run that lost its own", ctx do
    runner = create_run(ctx)

    # See the dispatch worker's own test for why `scheduled_at` is backdated too:
    # this repo has a unique index on `oban_jobs (args, scheduled_at, worker)` and
    # `now()` is frozen for the sandbox transaction.
    Repo.update_all(
      from(j in "oban_jobs",
        where: j.worker == "NervesHub.Workers.ScriptRunnerDispatch",
        where: fragment("(? ->> 'script_runner_id')::bigint = ?", j.args, ^runner.id)
      ),
      set: [state: "discarded", scheduled_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :minute)]
    )

    assert dispatch_jobs_for(runner) == []

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})

    assert [_job] = dispatch_jobs_for(runner)
  end

  test "leaves a run that still has a pacer alone", ctx do
    runner = create_run(ctx)

    assert :ok = perform_job(RequeueStrandedScriptRunners, %{})

    assert [_only_one] = dispatch_jobs_for(runner)
  end
end
