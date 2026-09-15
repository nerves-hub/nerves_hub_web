defmodule NervesHub.Workers.FirmwareDeltaBuilder do
  use Oban.Worker,
    queue: :firmware,
    max_attempts: 3,
    unique: [
      period: 60 * 10,
      states: [:available, :scheduled, :executing, :suspended, :retryable],
      keys: [:source_id, :target_id],
      fields: [:worker, :args]
    ]

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: %{"source_id" => source_id, "target_id" => target_id}} = job) do
    source = Firmwares.get_firmware!(source_id)
    target = Firmwares.get_firmware!(target_id)

    # Deleting firmware retires the row but removes the file, so there is nothing
    # left to build from. `delete_firmware/2` takes the delta rows with it, which
    # makes most of these jobs a no-op at the lookup below, but a job already
    # executing when the delete lands would otherwise run the whole build against
    # a file that is on its way out.
    cond do
      Firmware.deleted?(source) -> {:cancel, "source firmware #{source.uuid} has been deleted"}
      Firmware.deleted?(target) -> {:cancel, "target firmware #{target.uuid} has been deleted"}
      true -> build_delta(source, target, job, id)
    end
  end

  defp build_delta(source, target, job, id) do
    Logger.metadata(
      product_id: source.product_id,
      source_firmware: source.uuid,
      source_version: source.version,
      target_firmware: target.uuid,
      target_version: target.version,
      job_id: id
    )

    case Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id) do
      {:ok, %FirmwareDelta{status: :processing} = delta} ->
        Logger.info(
          "Processing delta #{source.version} to #{target.version}; attempt number #{job.attempt}/#{job.max_attempts}"
        )

        # if on last attempt and delta hasn't been marked as failed, fail it
        case Firmwares.generate_firmware_delta(delta, source, target) do
          {:error, :no_delta_support_in_firmware} ->
            Logger.info("Delta generation failed. No delta support detected.")
            _ = fail_delta(delta)
            :discard

          {:error, _} = err ->
            delta_failed(delta, job, err)

          ok ->
            ok
        end

      # Currently we do not retry timed out or failed delta builds
      # This could lead to generating too many times
      {:ok, %FirmwareDelta{status: _}} ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp delta_failed(delta, job, err) do
    case Repo.reload(delta) do
      # Its firmware was deleted mid-build, taking the delta row with it.
      nil ->
        {:cancel, "the delta was deleted while building"}

      delta ->
        _ =
          if job.attempt >= job.max_attempts and delta.status != :failed do
            Logger.warning("Delta generation failed on final attempt, marking as failed")
            {:ok, _} = Firmwares.fail_firmware_delta(delta)
          end

        Logger.warning("Delta generation failed: #{inspect(err)}")
        err
    end
  end

  # Reloaded first because the delta row goes with its firmware, so a delete
  # landing mid-build leaves nothing to mark failed.
  defp fail_delta(delta) do
    case Repo.reload(delta) do
      nil -> :ok
      delta -> {:ok, _} = Firmwares.fail_firmware_delta(delta)
    end
  end
end
