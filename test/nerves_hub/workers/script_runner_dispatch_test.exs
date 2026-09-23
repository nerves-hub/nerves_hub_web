defmodule NervesHub.Workers.ScriptRunnerDispatchTest do
  @moduledoc """
  Pacing a run.

  The `script_runners` queue limit caps how many scripts run at once; this worker
  decides how many of them belong to each run. What is asserted here is how many
  device jobs a pass inserts, since that is the whole fair-share mechanism.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.Workers.ScriptRunnerDevice
  alias NervesHub.Workers.ScriptRunnerDispatch

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{user: user, org: org, product: product, firmware: firmware}
  end

  # Read from the worker rather than restated, so these stay true if the queue
  # limit in config is retuned.
  defp ceiling(), do: ScriptRunnerDispatch.ceiling()

  defp run_with(ctx, device_count) do
    tag = "run-#{System.unique_integer([:positive])}"

    for _ <- 1..device_count do
      Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, %{tags: [tag]})
    end

    {:ok, runner, []} =
      ScriptRunners.create(ctx.product, ctx.user, %{
        text: "IO.puts(:hi)",
        filter_type: :tags,
        filter: %{tags: [tag], tag_operator: :or}
      })

    runner
  end

  defp dispatch(runner) do
    perform_job(ScriptRunnerDispatch, %{"script_runner_id" => runner.id})
  end

  defp device_jobs_for(runner) do
    all_enqueued(worker: ScriptRunnerDevice)
    |> Enum.filter(&(&1.args["script_runner_id"] == runner.id))
  end

  defp reload(runner), do: Repo.get!(ScriptRunner, runner.id)

  describe "pacing a single run" do
    test "a lone run gets the whole ceiling", ctx do
      runner = run_with(ctx, 3)

      assert {:snooze, _} = dispatch(runner)

      # Fewer devices than the ceiling, so all of them go at once.
      assert length(device_jobs_for(runner)) == 3
      assert ScriptRunners.status_counts(runner) == %{running: 3}
    end

    test "never queues more than the ceiling at a time", ctx do
      runner = run_with(ctx, ceiling() + 25)

      assert {:snooze, _} = dispatch(runner)

      assert length(device_jobs_for(runner)) == ceiling(),
             "a run larger than the ceiling must not queue every device at once"

      assert ScriptRunners.pending_device_count(runner.id) == 25
    end

    test "tops up as devices finish, and finishes the run", ctx do
      runner = run_with(ctx, 4)

      assert {:snooze, _} = dispatch(runner)
      assert length(device_jobs_for(runner)) == 4

      # Answer every device, as the device jobs would.
      for result <- ScriptRunners.device_results(runner) do
        ScriptRunners.record_device_result(runner.id, result.device_id, :completed, "done")
      end

      assert :ok = dispatch(runner)

      assert reload(runner).status == :completed
      assert reload(runner).finished_at
    end

    test "marks the run running on its first pass", ctx do
      runner = run_with(ctx, 1)
      assert reload(runner).status == :pending

      assert {:snooze, _} = dispatch(runner)

      assert reload(runner).status == :running
      assert reload(runner).started_at
    end

    test "does not re-dispatch devices already out", ctx do
      runner = run_with(ctx, 3)

      assert {:snooze, _} = dispatch(runner)
      assert length(device_jobs_for(runner)) == 3

      # Nothing has answered yet, so a second pass has no room and nothing to claim.
      assert {:snooze, _} = dispatch(runner)

      assert length(device_jobs_for(runner)) == 3,
             "a device already dispatched must not be sent the script twice"
    end
  end

  describe "sharing between concurrent runs" do
    test "two runs each get half the ceiling", ctx do
      first = run_with(ctx, ceiling())
      second = run_with(ctx, ceiling())

      assert {:snooze, _} = dispatch(first)
      assert {:snooze, _} = dispatch(second)

      assert length(device_jobs_for(first)) == div(ceiling(), 2)
      assert length(device_jobs_for(second)) == div(ceiling(), 2)
    end

    test "four runs each get a quarter", ctx do
      runners = for _ <- 1..4, do: run_with(ctx, ceiling())

      for runner <- runners, do: assert({:snooze, _} = dispatch(runner))

      for runner <- runners do
        assert length(device_jobs_for(runner)) == div(ceiling(), 4)
      end

      total = Enum.sum(Enum.map(runners, &length(device_jobs_for(&1))))

      assert total == ceiling(), "the shares must add up to the ceiling, not exceed it"
    end

    test "a small run is not starved behind a huge one", ctx do
      huge = run_with(ctx, ceiling() * 2)
      small = run_with(ctx, 5)

      assert {:snooze, _} = dispatch(huge)
      assert {:snooze, _} = dispatch(small)

      # This is the whole reason the dispatcher exists: with a single queue and no
      # pacing, the huge run would hold every slot and the small one would wait for
      # all of it.
      assert length(device_jobs_for(small)) == 5
      assert length(device_jobs_for(huge)) == div(ceiling(), 2)
    end

    test "a share grows back as other runs finish", ctx do
      first = run_with(ctx, ceiling() * 2)
      second = run_with(ctx, ceiling())

      assert {:snooze, _} = dispatch(first)
      assert length(device_jobs_for(first)) == div(ceiling(), 2)

      # The other run finishing hands its half back.
      {:ok, _second} = ScriptRunners.mark_finished(second)

      for result <- ScriptRunners.device_results(first), result.status == :running do
        ScriptRunners.record_device_result(first.id, result.device_id, :completed, "done")
      end

      assert {:snooze, _} = dispatch(first)

      assert length(device_jobs_for(first)) == div(ceiling(), 2) + ceiling(),
             "with the other run gone, the whole ceiling is available again"
    end

    test "devices already out count against a shrinking share", ctx do
      runner = run_with(ctx, ceiling())

      # Alone at first: takes the whole ceiling.
      assert {:snooze, _} = dispatch(runner)
      assert length(device_jobs_for(runner)) == ceiling()

      # Three more runs appear, so the share drops to a quarter. The devices
      # already on their way are not recalled -- they will answer either way -- so
      # this pass must simply add nothing.
      for _ <- 1..3, do: run_with(ctx, 10)

      assert {:snooze, _} = dispatch(runner)

      assert length(device_jobs_for(runner)) == ceiling(),
             "a shrunk share must stop new dispatches, not cancel ones in flight"
    end
  end

  describe "recovery" do
    test "a device stuck running is released and dispatched again", ctx do
      runner = run_with(ctx, 2)

      claimed = ScriptRunners.claim_pending_devices(runner.id, 2)

      # Backdate the claim, standing in for a node that died holding these rows.
      Repo.update_all(
        from(srd in NervesHub.ScriptRunners.ScriptRunnerDevice, where: srd.script_runner_id == ^runner.id),
        set: [started_at: DateTime.add(DateTime.utc_now(), -10, :minute)]
      )

      assert {:snooze, _} = dispatch(runner)

      # Picked back up rather than stranded: this is what replaces abandoning a
      # run when its node dies.
      assert Enum.sort(Enum.map(device_jobs_for(runner), & &1.args["device_id"])) == Enum.sort(claimed)
    end
  end

  describe "a run that has gone away" do
    test "cancels itself when the run no longer exists", _ctx do
      assert {:cancel, message} = dispatch(%ScriptRunner{id: 0, text: ""})
      assert message =~ "no longer exists"
    end

    test "does nothing for a run already completed", ctx do
      runner = run_with(ctx, 1)
      {:ok, runner} = ScriptRunners.mark_finished(runner)

      assert :ok = dispatch(runner)
      assert device_jobs_for(runner) == []
    end
  end

  describe "ceiling/0" do
    setup do
      original = Application.fetch_env!(:nerves_hub, Oban)
      on_exit(fn -> Application.put_env(:nerves_hub, Oban, original) end)

      %{original: original}
    end

    defp put_queues(config, queues) do
      Application.put_env(:nerves_hub, Oban, Keyword.put(config, :queues, queues))
    end

    test "is the configured queue limit", ctx do
      assert ScriptRunnerDispatch.ceiling() ==
               ctx.original |> Keyword.fetch!(:queues) |> Keyword.fetch!(:script_runners)
    end

    test "follows the config rather than a copy of the number", ctx do
      put_queues(ctx.original, script_runners: 42)

      assert ScriptRunnerDispatch.ceiling() == 42,
             "retuning the queue limit must retune the share, or the two drift apart"
    end

    test "reads the limit out of a queue configured with options", ctx do
      put_queues(ctx.original, script_runners: [limit: 17])

      assert ScriptRunnerDispatch.ceiling() == 17
    end

    test "falls back to a sane number when the queue is not configured", ctx do
      put_queues(ctx.original, other: 1)

      assert ScriptRunnerDispatch.ceiling() == 500,
             "a missing queue must not make the share arithmetic divide by nil"
    end
  end

  test "carries the run's own text, so an edited script cannot change a run", ctx do
    runner = run_with(ctx, 1)

    assert {:snooze, _} = dispatch(runner)

    [job] = device_jobs_for(runner)
    assert job.args["text"] == runner.text
  end
end
