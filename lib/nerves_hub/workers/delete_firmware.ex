defmodule NervesHub.Workers.DeleteFirmware do
  use Oban.Worker,
    max_attempts: 5,
    queue: :delete_firmware

  @uploader Application.compile_env!(:nerves_hub_www, :firmware_upload)

  @impl true
  def perform(%Oban.Job{args: args}), do: @uploader.delete_file(args)
end
