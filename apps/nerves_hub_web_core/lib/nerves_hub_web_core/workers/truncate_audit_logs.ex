defmodule NervesHubWebCore.Workers.TruncateAuditLogs do
  use NervesHubWebCore.Worker,
    args: %{run_utc_time: "01:00:00.000000"},
    max_attempts: 5,
    queue: :truncate,
    schedule: "0 */3 * * *"

  @impl true
  def run(_) do
    config = Application.get_env(:nerves_hub_web_core, __MODULE__)
    if config[:enabled], do: NervesHubWebCore.AuditLogs.truncate(config), else: :ok
  end
end
