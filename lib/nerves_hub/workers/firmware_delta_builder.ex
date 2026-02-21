max_attempts = 3

defmodule NervesHub.Workers.FirmwareDeltaBuilder do
  use Oban.Worker,
    max_attempts: unquote(max_attempts),
    queue: :firmware_delta_builder,
    unique: [
      period: 60 * 10,
      states: [:available, :scheduled, :executing],
      keys: [:source_id, :target_id],
      fields: [:worker, :args]
    ]

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Repo

  require Logger

  @max_attempts max_attempts

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

    case Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id) do
      {:ok, %FirmwareDelta{status: :processing} = delta} ->
        Logger.info(
          "Processing delta #{source.version} to #{target.version}; attempt number #{attempt}/#{@max_attempts}"
        )

        # if on last attempt and delta hasn't been marked as failed, fail it
        case Firmwares.generate_firmware_delta(delta, source, target) do
          {:error, :no_delta_support_in_firmware} ->
            delta = Repo.reload(delta)
            Logger.info("Delta generation failed. No delta support detected.")
            {:ok, _} = Firmwares.fail_firmware_delta(delta)
            :discard

          {:error, _} = err ->
            delta = Repo.reload(delta)

            _ =
              if attempt >= @max_attempts and delta.status != :failed do
                Logger.warning("Delta generation failed on final attempt, marking as failed")
                {:ok, _} = Firmwares.fail_firmware_delta(delta)
              end

            Logger.warning("Delta generation failed: #{inspect(err)}")
            err

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
end
