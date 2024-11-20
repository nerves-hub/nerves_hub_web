defmodule NervesHubWeb.DeploymentController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.ManagedDeployments

  plug(:validate_role, org: :view)

  def export_audit_logs(
        %{assigns: %{org: org, product: product}} = conn,
        %{"name" => deployment_name}
      ) do
    {:ok, deployment} = ManagedDeployments.get_deployment_by_name(product, deployment_name)

    case AuditLogs.logs_for(deployment) do
      [] ->
        conn
        |> put_flash(:error, "No audit logs exist for this deployment.")
        |> redirect(to: ~p"/org/#{org.name}/#{product.name}/deployment_groups")

      audit_logs ->
        audit_logs = AuditLogs.format_for_csv(audit_logs)

        send_download(conn, {:binary, audit_logs}, filename: "#{deployment.name}-audit-logs.csv")
    end
  end
end
