defmodule NervesHub.Workers.TruncateAuditLogs do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  alias NervesHub.Config

  @impl true
  def perform(_) do
    vapor_config = Vapor.load!(Config)
    config = vapor_config.audit_logs

    if config.enabled do
      NervesHub.AuditLogs.truncate(config)
    end

    :ok
  end
end
