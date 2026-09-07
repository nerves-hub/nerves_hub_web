defmodule NervesHubWeb.DeploymentGroupController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.ManagedDeployments

  plug(:validate_role, org: :view)

  def export_audit_logs(%{assigns: %{current_scope: %{org: org, product: product}}} = conn, %{"name" => deployment_name}) do
    case ManagedDeployments.get_deployment_group_by_name(product, deployment_name) do
      {:ok, deployment_group} ->
        send_audit_logs(conn, org, product, deployment_group)

      {:error, :not_found} ->
        raise NervesHubWeb.NotFoundError
    end
  end

  defp send_audit_logs(conn, org, product, deployment_group) do
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
