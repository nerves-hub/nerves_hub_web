defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorRegistrationTest do
  use NervesHub.DataCase
  use Mimic

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration

  test "logs to sentry and restarts orchestrator processes" do
    expect(ProcessHub, :process_list, fn _table_name, _node_context ->
      []
    end)

    expect(ManagedDeployments, :should_run_orchestrator, 2, fn ->
      [%ManagedDeployments.DeploymentGroup{}]
    end)

    expect(Sentry, :capture_message, fn _message, [extra: extra, result: :none] ->
      assert extra.process_count == 0
      assert extra.deployment_count == 1
    end)

    expect(ProcessHub, :start_children, fn _hub_id, _spec, _opts -> :ok end)

    expect(ProcessHub, :process_list, fn _table_name, _node_context ->
      []
    end)

    expect(ProcessHub.Future, :await, fn _ ->
      %ProcessHub.StartResult{
        status: :ok,
        started: [{"my_child", ["node2@127.0.0.1": "pid"]}],
        errors: [],
        rollback: false
      }
    end)

    OrchestratorRegistration.check_running_orchestrators()
  end
end
