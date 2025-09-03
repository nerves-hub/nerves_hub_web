defmodule NervesHub.Workers.OrgAuditLogTruncation do
  use Oban.Worker,
    max_attempts: 5,
    queue: :truncate

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"days_to_keep" => days_to_keep, "org_id" => id}}) do
    {:ok, _} = NervesHub.AuditLogs.truncate(id, days_to_keep)

    :ok
  end
end
