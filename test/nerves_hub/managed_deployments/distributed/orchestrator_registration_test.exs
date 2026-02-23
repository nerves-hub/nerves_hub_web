defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorRegistrationTest do
  use NervesHub.DataCase
  use Mimic

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration

  test "doesn't start orchestrator processes if they are already running" do
    expect(ManagedDeployments, :should_run_orchestrator, 1, fn ->
      [%ManagedDeployments.DeploymentGroup{id: 1}]
    end)

    expect(ProcessHub, :process_list, fn _table_name, _node_context ->
      [distributed_orchestrator_1: ["nerves-hub@node.id": "1.2.3"]]
    end)

    reject(&ProcessHub.start_children/3)

    OrchestratorRegistration.start_orchestrators()
  end

  test "starts the orchestrator process if it isn't already running" do
    expect(ManagedDeployments, :should_run_orchestrator, 1, fn ->
      [%ManagedDeployments.DeploymentGroup{id: 1}]
    end)

    expect(ProcessHub, :process_list, fn _table_name, _node_context ->
      [distributed_orchestrator_2: ["nerves-hub@node.id": "1.2.3"]]
    end)

    expect(ProcessHub, :start_children, fn :deployment_orchestrators, _specs, _opts ->
      :fake_result
    end)

    expect(ProcessHub.Future, :await, fn _result ->
      :fake_result
    end)

    expect(ProcessHub.StartResult, :format, fn _result ->
      {:ok, :fake_list}
    end)

    OrchestratorRegistration.start_orchestrators()
  end

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
