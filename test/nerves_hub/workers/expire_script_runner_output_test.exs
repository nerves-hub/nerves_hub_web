defmodule NervesHub.Workers.ExpireScriptRunnerOutputTest do
  # Not async: the retention period is read from the application environment,
  # and one test changes it.
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.Workers.ExpireScriptRunnerOutput

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    for _ <- 1..2, do: Fixtures.device_fixture(org, product, firmware, %{tags: ["expire"]})

    {:ok, runner, []} =
      ScriptRunners.create(product, user, %{
        name: "Expire",
        text: "System.get_env()",
        filter_type: :tags,
        filter: %{tags: ["expire"], tag_operator: :or}
      })

    [old, recent] = ScriptRunners.device_results(runner)

    1 = ScriptRunners.record_device_result(runner.id, old.device_id, :completed, "SECRET=old")
    1 = ScriptRunners.record_device_result(runner.id, recent.device_id, :completed, "SECRET=recent")

    finished_days_ago(old, 4)
    finished_days_ago(recent, 2)

    %{runner: runner, old: old, recent: recent}
  end

  defp finished_days_ago(result, days) do
    Repo.update_all(where(ScriptRunnerDevice, [srd], srd.id == ^result.id),
      set: [finished_at: DateTime.add(DateTime.utc_now(), -days, :day)]
    )
  end

  defp reload(result), do: Repo.get!(ScriptRunnerDevice, result.id)

  test "clears output older than the retention period and keeps the rest of the row", ctx do
    assert :ok = perform_job(ExpireScriptRunnerOutput, %{})

    old = reload(ctx.old)
    assert old.output == nil
    assert old.output_expired_at
    # The record of what ran stays.
    assert old.status == :completed
    assert old.finished_at

    recent = reload(ctx.recent)
    assert recent.output == "SECRET=recent"
    assert recent.output_expired_at == nil
  end

  test "the retention period comes from the application environment", ctx do
    previous = Application.get_env(:nerves_hub, :script_runner_output_days_to_retain)
    Application.put_env(:nerves_hub, :script_runner_output_days_to_retain, 1)
    on_exit(fn -> Application.put_env(:nerves_hub, :script_runner_output_days_to_retain, previous) end)

    assert :ok = perform_job(ExpireScriptRunnerOutput, %{})

    assert reload(ctx.old).output == nil
    assert reload(ctx.recent).output == nil
  end

  test "a device that never sent output is left alone", ctx do
    1 = ScriptRunners.record_device_result(ctx.runner.id, ctx.old.device_id, :timed_out, nil)
    finished_days_ago(ctx.old, 4)

    assert :ok = perform_job(ExpireScriptRunnerOutput, %{})

    # No output was ever there, so it was not removed either.
    assert reload(ctx.old).output_expired_at == nil
  end

  test "clears at most the limit in one pass", ctx do
    finished_days_ago(ctx.recent, 4)

    assert ScriptRunners.expire_output(to_timeout(day: 3), 1) == 1
    assert ScriptRunners.expire_output(to_timeout(day: 3), 1) == 1
    assert ScriptRunners.expire_output(to_timeout(day: 3), 1) == 0

    assert reload(ctx.old).output == nil
    assert reload(ctx.recent).output == nil
  end
end
