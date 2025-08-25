defmodule NervesHub.Workers.FirmwareDeltaBuilder do
  use Oban.Worker,
    max_attempts: 5,
    queue: :firmware_delta_builder,
    unique: [
      period: 60 * 10,
      states: [:available, :scheduled, :executing]
    ]

  require Logger
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.ManagedDeployments

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: %{"source_id" => source_id, "target_id" => target_id}}) do
    source = Firmwares.get_firmware!(source_id)
    target = Firmwares.get_firmware!(target_id)

    Logger.metadata(
      product_id: source.product_id,
      source_firmware: source.uuid,
      target_firmware: target.uuid,
      job_id: id
    )

    :ok = maybe_create_firmware_delta(source, target)

    Enum.each(ManagedDeployments.get_deployment_groups_by_firmware(target_id), fn deployment ->
      ManagedDeployments.broadcast(deployment, "deployments/update")
    end)

    :ok
  end

  def start(source_id, target_id) do
    {:ok, _job} =
      %{source_id: source_id, target_id: target_id}
      |> __MODULE__.new()
      |> Oban.insert()

    :ok
  end

  defp maybe_create_firmware_delta(source, target) do
    case Firmwares.get_firmware_delta_by_source_and_target(source, target) do
      {:ok, %FirmwareDelta{status: :processing} = delta} ->
        Logger.info(
          "Attempting firmware delta build for #{source.platform} #{source.version} to #{target.version}..."
        )

        :ok = Firmwares.generate_firmware_delta(delta, source, target)

      # Currently we do not retry timed out or failed delta builds
      # This could lead to generating too many times
      {:ok, %FirmwareDelta{status: _}} ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end
end
