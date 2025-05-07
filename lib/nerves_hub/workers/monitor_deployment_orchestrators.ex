defmodule NervesHub.Workers.MonitorDeploymentOrchestrators do
  @moduledoc false

  use Oban.Worker,
    max_attempts: 1,
    queue: :default

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration

  @impl Oban.Worker
  def perform(_) do
    process_count = ProcessHub.process_list(:deployment_orchestrators, :global) |> Enum.count()
    deployment_count = ManagedDeployments.should_run_orchestrator() |> Enum.count()

    if process_count != deployment_count do
      _ =
        Sentry.capture_message("Not enough Orchestrator processes are running",
          extra: %{process_count: process_count, deployment_count: deployment_count},
          result: :none
        )

      :ok = OrchestratorRegistration.start_orchestrators()
    end

    :ok
  end
end
