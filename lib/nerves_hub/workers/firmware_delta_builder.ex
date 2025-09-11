defmodule NervesHub.Workers.FirmwareDeltaBuilder do
  @max_attempts 3

  use Oban.Worker,
    max_attempts: @max_attempts,
    queue: :firmware_delta_builder,
    unique: [
      period: 60 * 10,
      states: [:available, :scheduled, :executing],
      keys: [:source_id, :target_id],
      fields: [:worker, :args]
    ]

  require Logger
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.FirmwareDelta
  # alias NervesHub.ManagedDeployments

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, attempt: attempt, args: %{"source_id" => source_id, "target_id" => target_id}}) do
    source = Firmwares.get_firmware!(source_id)
    target = Firmwares.get_firmware!(target_id)

    Logger.metadata(
      product_id: source.product_id,
      source_firmware: source.uuid,
      source_version: source.version,
      target_firmware: target.uuid,
      target_version: target.version,
      job_id: id
    )

    case Firmwares.get_firmware_delta_by_source_and_target(source, target) do
      {:ok, %FirmwareDelta{status: :processing} = delta} ->
        Logger.info(
          "Processing delta #{source.version} to #{target.version}; attempt number #{attempt}/#{@max_attempts}"
        )

        Firmwares.generate_firmware_delta(delta, source, target)

      # Currently we do not retry timed out or failed delta builds
      # This could lead to generating too many times
      {:ok, %FirmwareDelta{status: _}} ->
        :ok

      {:error, :not_found} ->
        :ok
    end

    # Enum.each(ManagedDeployments.get_deployment_groups_by_firmware(target_id), fn deployment ->
    #   ManagedDeployments.broadcast(deployment, "deployments/update")
    # end)
  end
end
