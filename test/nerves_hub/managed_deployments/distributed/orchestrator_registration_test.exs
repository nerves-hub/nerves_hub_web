defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorRegistrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration

  # ---- filter_already_started_errors ----
  # These private helpers are exercised via start_orchestrators/0 and check_running_orchestrators/0.
  # We stub ProcessHub and ManagedDeployments to control inputs.

  describe "start_orchestrators/0 — filter_already_started_errors" do
    test "returns :ok when no orchestrators need starting" do
      stub(ManagedDeployments, :should_run_orchestrator, fn -> [] end)
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [] end)

      assert :ok = OrchestratorRegistration.start_orchestrators()
    end

    test "starts new orchestrators that are not yet running" do
      deployment = %{id: 1}
      spec = Orchestrator.child_spec(deployment)

      stub(ManagedDeployments, :should_run_orchestrator, fn -> [deployment] end)
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [] end)

      future_ref = make_ref()
      stub(ProcessHub, :start_children, fn :deployment_orchestrators, [^spec], _ -> future_ref end)

      stub(ProcessHub.Future, :await, fn ^future_ref -> {:ok, [spec.id]} end)
      stub(ProcessHub.StartResult, :format, fn {:ok, [_id]} -> {:ok, [spec.id]} end)

      assert :ok = OrchestratorRegistration.start_orchestrators()
    end

    test "skips orchestrators that are already running" do
      deployment = %{id: 2}
      spec = Orchestrator.child_spec(deployment)

      stub(ManagedDeployments, :should_run_orchestrator, fn -> [deployment] end)
      # Return spec.id as already running so it gets filtered out
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [{spec.id, %{}}] end)

      # ProcessHub.start_children should NOT be called since nothing requires starting
      reject(ProcessHub, :start_children, 3)

      assert :ok = OrchestratorRegistration.start_orchestrators()
    end

    test "filters :already_started errors and returns :ok" do
      deployment = %{id: 3}
      spec = Orchestrator.child_spec(deployment)
      pid = self()

      stub(ManagedDeployments, :should_run_orchestrator, fn -> [deployment] end)
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [] end)

      future_ref = make_ref()
      stub(ProcessHub, :start_children, fn :deployment_orchestrators, [^spec], _ -> future_ref end)
      stub(ProcessHub.Future, :await, fn ^future_ref -> :awaited end)
      # format returns the shape that filter_already_started_errors handles
      stub(ProcessHub.StartResult, :format, fn :awaited ->
        {:error, {[{spec.id, {:already_started, pid}}], []}}
      end)

      assert :ok = OrchestratorRegistration.start_orchestrators()
    end

    test "logs and reports error when non-already-started error occurs" do
      deployment = %{id: 4}
      spec = Orchestrator.child_spec(deployment)

      stub(ManagedDeployments, :should_run_orchestrator, fn -> [deployment] end)
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [] end)

      future_ref = make_ref()
      stub(ProcessHub, :start_children, fn :deployment_orchestrators, [^spec], _ -> future_ref end)
      stub(ProcessHub.Future, :await, fn ^future_ref -> {:error, {[{spec.id, :some_real_error}], []}} end)
      stub(ProcessHub.StartResult, :format, fn _ -> {:error, {[{spec.id, :some_real_error}], []}} end)
      stub(Sentry, :capture_message, fn _, _ -> :ok end)

      assert :ok = OrchestratorRegistration.start_orchestrators()
    end
  end

  describe "check_running_orchestrators/0" do
    test "returns :ok when process count matches deployment count" do
      stub(ManagedDeployments, :should_run_orchestrator, fn -> [%{id: 1}, %{id: 2}] end)
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [{1, %{}}, {2, %{}}] end)

      # Should NOT call start_orchestrators path (no mismatch)
      assert :ok = OrchestratorRegistration.check_running_orchestrators()
    end

    test "calls start_orchestrators and reports mismatch when count differs" do
      stub(ManagedDeployments, :should_run_orchestrator, fn -> [%{id: 1}, %{id: 2}] end)
      # Only one process running, two expected
      stub(ProcessHub, :process_list, fn :deployment_orchestrators, :global -> [{1, %{}}] end)

      stub(Sentry, :capture_message, fn "Not enough Orchestrator processes are running", _ -> :ok end)

      # start_orchestrators will be called — stub it out
      stub(ProcessHub, :start_children, fn :deployment_orchestrators, _specs, _ -> make_ref() end)
      stub(ProcessHub.Future, :await, fn _ref -> {:ok, []} end)
      stub(ProcessHub.StartResult, :format, fn _ -> {:ok, []} end)

      assert :ok = OrchestratorRegistration.check_running_orchestrators()
    end
  end
end
