defmodule NervesHubWeb.DeploymentGroupController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.ManagedDeployments

  plug(:validate_role, org: :view)

  def export_audit_logs(%{assigns: %{org: org, product: product}} = conn, %{"name" => deployment_name}) do
    {:ok, deployment_group} =
      ManagedDeployments.get_deployment_group_by_name(product, deployment_name)

    case AuditLogs.logs_for(deployment_group) do
      [] ->
        conn
        |> put_flash(:error, "No audit logs exist for this deployment group.")
        |> redirect(to: ~p"/org/#{org}/#{product}/deployment_groups")

      audit_logs ->
        audit_logs = AuditLogs.format_for_csv(audit_logs)

        send_download(conn, {:binary, audit_logs}, filename: "#{deployment_group.name}-audit-logs.csv")
    end
  end
end
