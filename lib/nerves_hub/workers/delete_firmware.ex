defmodule NervesHub.Workers.DeleteFirmware do
  use Oban.Worker,
    max_attempts: 5,
    queue: :delete_firmware

  @impl true
  def perform(%Oban.Job{args: args}) do
    uploader = Application.fetch_env!(:nerves_hub, :firmware_upload)
    uploader.delete_file(args)
  end
end
