defmodule NervesHub.Workers.FirmwareDeltaTimeout do
  use Oban.Worker,
    max_attempts: 5,
    queue: :firmware_delta_timeout

  alias NervesHub.Firmwares

  # 15min timeout
  @delta_generation_timeout 960

  @impl Oban.Worker
  def perform(_) do
    _ = Firmwares.time_out_firmware_delta_generations(@delta_generation_timeout, :second)

    :ok
  end
end
