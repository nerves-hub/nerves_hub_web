defmodule NervesHub.Workers.TruncateAuditLogs do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  @impl true
  def perform(_) do
    if config()[:enabled] do
      NervesHub.AuditLogs.truncate(config())
    end

    :ok
  end

  defp config(), do: Application.get_env(:nerves_hub, :audit_logs)
end
