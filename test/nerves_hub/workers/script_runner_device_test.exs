defmodule NervesHub.Workers.ScriptRunnerDeviceTest do
  @moduledoc """
  Running one device's script. The device is stood in for by this test process:
  the script is broadcast on `device:<id>`, so subscribing makes the dispatch
  visible, and replying to the runner pid that arrives with it is what a device
  answering looks like from the platform's side.
  """

  use NervesHub.DataCase, async: false
  use Mimic

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.Scripts.Runner
  alias NervesHub.Workers.ScriptRunnerDevice
  alias NervesHub.Workers.ScriptRunnerDispatch

  setup :set_mimic_global

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{user: user, org: org, product: product, firmware: firmware}
  end

  defp run_for(ctx, device_params) do
    device = Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, Map.merge(%{tags: ["run"]}, device_params))

    {:ok, runner, []} =
      ScriptRunners.create(ctx.product, ctx.user, %{
        name: "Say hi",
        text: "IO.puts(:hi)",
        filter_type: :tags,
        filter: %{tags: ["run"], tag_operator: :or}
      })

    # What dispatch does before inserting the job: a device job only ever runs for
    # a row it holds at `:running`.
    [_device_id] = ScriptRunners.claim_pending_devices(runner.id, 1)

    %{device: device, runner: runner}
  end

  defp perform(runner, device) do
    perform_job(ScriptRunnerDevice, %{"script_runner_id" => runner.id, "device_id" => device.id})
  end

  defp result(runner) do
    [result] = ScriptRunners.device_results(runner)
    result
  end

  test "records the device's output", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

    task = Task.async(fn -> perform(runner, device) end)

    assert_receive {:run_script, runner_pid, "IO.puts(:hi)", timeout}, 2_000
    assert timeout == to_timeout(second: 30), "the device must get the full budget, not the old 15s cap"

    send(runner_pid, {:output, "up 3 days"})

    assert :ok = Task.await(task, 5_000)

    result = result(runner)
    assert result.status == :completed
    assert result.output == "up 3 days"
    assert result.finished_at
  end

  # PostgreSQL rejects both in a `text` column. A failed write would crash the
  # job and leave the row at `:running`, to be released and sent again.
  test "output with a NUL byte or invalid UTF-8 is stored scrubbed", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    stub(Runner, :send, fn _device, _command, _opts ->
      {:ok, "abc" <> <<0>> <> "def" <> <<0xFF>> <> "ghi"}
    end)

    assert :ok = perform(runner, device)

    result = result(runner)
    assert result.status == :completed
    assert result.output == "abcdef�ghi"
  end

  test "output past the cap is truncated, without splitting a character", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    max = ScriptRunners.max_output_bytes()

    # "é" is two bytes, so the cut lands inside one.
    output = String.duplicate("a", max - 1) <> "é" <> "after the cap"

    stub(Runner, :send, fn _device, _command, _opts -> {:ok, output} end)

    assert :ok = perform(runner, device)

    stored = result(runner).output

    assert String.valid?(stored)
    assert String.starts_with?(stored, String.duplicate("a", max - 1) <> "\n")
    refute stored =~ "after the cap"
    assert stored =~ "[output truncated at 32 KB]"
  end

  test "output at the cap is kept whole", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    output = String.duplicate("a", ScriptRunners.max_output_bytes())

    stub(Runner, :send, fn _device, _command, _opts -> {:ok, output} end)

    assert :ok = perform(runner, device)

    assert result(runner).output == output
  end

  test "an offline device is recorded without being sent anything", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device, %{status: :disconnected})

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

    assert :ok = perform(runner, device)

    refute_received {:run_script, _, _, _}, "nothing should be sent to a device that is not connected"

    result = result(runner)
    assert result.status == :offline
    assert result.output == nil
    assert result.finished_at
  end

  test "a device that has never connected is offline", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})

    assert :ok = perform(runner, device)
    assert result(runner).status == :offline
  end

  test "a device whose connection drops between creation and dispatch is offline", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    connection = Fixtures.device_connection_fixture(device)

    # Online when the run was created, gone by the time its turn came.
    Repo.update_all(
      from(dc in DeviceConnection, where: dc.id == ^connection.id),
      set: [status: :disconnected]
    )

    assert :ok = perform(runner, device)
    assert result(runner).status == :offline
  end

  test "a device too old to run scripts is unsupported, with no console fallback", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

    task = Task.async(fn -> perform(runner, device) end)

    assert_receive {:run_script, runner_pid, _text, _timeout}, 2_000

    # What `DeviceLink` sends back for a device below api 2.1.0.
    send(runner_pid, {:error, :incompatible_version})

    assert :ok = Task.await(task, 5_000)

    result = result(runner)
    assert result.status == :unsupported
    assert result.output == nil
  end

  test "a device that never answers is timed out", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    stub(Runner, :send, fn _device, _command, _opts ->
      {:error, "device did not respond in 30000 milliseconds"}
    end)

    assert :ok = perform(runner, device)

    result = result(runner)
    assert result.status == :timed_out
    # Nothing came back from the device, so there is nothing to record. The status
    # already says the device did not respond.
    assert result.output == nil
  end

  test "any other error is a failure", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    stub(Runner, :send, fn _device, _command, _opts ->
      {:error, "the wheels came off"}
    end)

    assert :ok = perform(runner, device)

    result = result(runner)
    assert result.status == :failed
    assert result.output =~ "wheels came off"
  end

  # The previous release carried the script on the job. Those jobs can still be
  # queued across a deploy, and must run the same way.
  test "runs a job queued with the script in its args", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    stub(Runner, :send, fn _device, %{text: "IO.puts(:hi)"}, _opts -> {:ok, "hi"} end)

    assert :ok =
             perform_job(ScriptRunnerDevice, %{
               "script_runner_id" => runner.id,
               "device_id" => device.id,
               "text" => runner.text
             })

    assert result(runner).status == :completed
  end

  test "a job whose run was deleted is cancelled without sending anything", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    {:ok, _} = ScriptRunners.delete(runner, ctx.user, ctx.product)

    reject(&Runner.send/3)

    assert {:cancel, _reason} = perform(runner, device)
  end

  test "a job whose device row is gone sends nothing", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)

    Repo.delete_all(from(srd in NervesHub.ScriptRunners.ScriptRunnerDevice, where: srd.script_runner_id == ^runner.id))

    reject(&Runner.send/3)

    assert {:cancel, _reason} = perform(runner, device)
  end

  # Review finding #4. A job that crashes after the script was sent used to have
  # its row released and the script sent again on every dispatch pass, forever.
  test "a job that crashes after sending is abandoned, not sent again", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})
    _ = Fixtures.device_connection_fixture(device)
    test_pid = self()

    # A shape `classify/1` has no clause for: the job raises after the send.
    stub(Runner, :send, fn _device, _command, _opts ->
      send(test_pid, :sent)
      {:error, :something_new}
    end)

    assert_raise FunctionClauseError, fn -> perform(runner, device) end
    assert_received :sent

    # The five minutes `release_stale_devices/2` waits before touching a row.
    # `perform_job/2` inserts no job row, so nothing counts as live.
    Repo.update_all(
      from(srd in NervesHub.ScriptRunners.ScriptRunnerDevice, where: srd.script_runner_id == ^runner.id),
      set: [started_at: DateTime.add(DateTime.utc_now(), -6, :minute)]
    )

    :ok = ScriptRunners.subscribe(runner)

    # Abandoning the device leaves nothing unfinished, so the same pass completes
    # the run rather than snoozing.
    assert :ok = perform_job(ScriptRunnerDispatch, %{"script_runner_id" => runner.id})

    assert result(runner).status == :abandoned
    assert all_enqueued(worker: ScriptRunnerDevice) == [], "the script must not be dispatched a second time"
    refute_received :sent
    assert_received {:script_runner, :device_finished, %{status: :abandoned}}
    assert Repo.reload!(runner).status == :completed
  end

  test "tells subscribers the device finished", ctx do
    %{device: device, runner: runner} = run_for(ctx, %{})

    :ok = ScriptRunners.subscribe(runner)

    assert :ok = perform(runner, device)

    runner_id = runner.id
    device_id = device.id

    assert_receive {:script_runner, :device_finished,
                    %{script_runner_id: ^runner_id, device_id: ^device_id, status: :offline}}
  end

  test "is never retried, so a script is not re-run on a device unasked", _ctx do
    # An operator's script running twice on a device because a job was retried is
    # not something to do quietly.
    assert ScriptRunnerDevice.__opts__()[:max_attempts] == 1
  end
end
