defmodule NervesHub.Workers.DeviceLogLinesTruncation do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  @impl Oban.Worker
  def perform(_) do
    {:ok, _} = NervesHub.Devices.LogLines.truncate(days_to_keep())

    :ok
  end

  def days_to_keep() do
    logging_config = Application.get_env(:nerves_hub, :extension_config)[:logging]
    logging_config[:days_to_keep]
  end
end
