defmodule NervesHub.Workers.OrgAuditLogTruncation do
  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"org_id" => id, "days_to_keep" => days_to_keep}}) do
    {:ok, _} = NervesHub.AuditLogs.truncate(id, days_to_keep)

    :ok
  end
end
