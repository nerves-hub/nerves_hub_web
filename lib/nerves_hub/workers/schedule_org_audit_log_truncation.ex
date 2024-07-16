defmodule NervesHub.Workers.ScheduleOrgAuditLogTruncation do
  use Oban.Worker,
    queue: :truncation

  alias NervesHub.Accounts
  alias NervesHub.Workers.OrgAuditLogTruncation

  @impl true
  def perform(_) do
    if enabled?() do
      orgs = Accounts.get_orgs()

      Enum.each(orgs, fn org ->
        {:ok, _} =
          org
          |> truncation_args()
          |> OrgAuditLogTruncation.new()
          |> Oban.insert()
      end)
    end
    :ok
  end

  defp truncation_args(org) do
    %{
      org_id: org.id,
      days_to_keep: days_to_keep(org)
    }
  end

  def days_to_keep(org) do
    org.audit_log_days_to_keep || config()[:default_days_kept]
  end

  defp enabled?(), do: config()[:enabled]

  defp config(), do: Application.get_env(:nerves_hub, :audit_logs)
end
