defmodule NervesHub.Workers.TruncateAuditLogs do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  @impl true
  def perform(_) do
    if enabled?(), do: NervesHub.AuditLogs.truncate(config)

    :ok
  end

  defp enabled?(), do: Application.get_env(:nerves_hub, :audit_logs)[:enabled]
end
