defmodule NervesHubWebCore.Workers.DeleteFirmware do
  use NervesHubWebCore.Worker,
    max_attempts: 5,
    queue: :delete_firmware,
    schedule: "*/15 * * * *"

  @uploader Application.fetch_env!(:nerves_hub_web_core, :firmware_upload)

  @impl true
  def run(%{args: args}), do: @uploader.delete_file(args)
end
