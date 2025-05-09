defmodule NervesHub.Workers.MonitorDeploymentOrchestratorsTest do
  use NervesHub.DataCase
  use Mimic

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration
  alias NervesHub.Workers.MonitorDeploymentOrchestrators

  test "logs to sentry and restarts orchestrator processes" do
    expect(ProcessHub, :process_list, fn _table_name, _node_context ->
      []
    end)

    expect(ManagedDeployments, :should_run_orchestrator, fn ->
      [%ManagedDeployments.DeploymentGroup{}]
    end)

    expect(Sentry, :capture_message, fn _message, extra: extra, result: :none ->
      assert extra.process_count == 0
      assert extra.deployment_count == 1
    end)

    expect(OrchestratorRegistration, :start_orchestrators, fn -> :ok end)

    MonitorDeploymentOrchestrators.perform(%Oban.Job{})
  end
end
