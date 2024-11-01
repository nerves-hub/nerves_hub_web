defmodule NervesHub.Workers.OrgAuditLogTruncation do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  @impl true
  def perform(%Oban.Job{args: %{"org_id" => id, "days_to_keep" => days_to_keep}}) do
    {:ok, _} = NervesHub.AuditLogs.truncate(id, days_to_keep)

    :ok
  end
end
