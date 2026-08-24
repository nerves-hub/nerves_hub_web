defmodule NervesHubWeb.DeploymentGroupController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.ManagedDeployments
  alias NimbleCSV.RFC4180, as: CSV

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

  def export_device_ids(%{assigns: %{current_scope: scope}} = conn, %{"name" => deployment_name}) do
    {:ok, deployment_group} =
      ManagedDeployments.get_deployment_group_by_name(scope.product, deployment_name)

    identifiers = ManagedDeployments.device_identifiers(deployment_group)

    csv =
      [["identifier"] | Enum.map(identifiers, &[&1])]
      |> CSV.dump_to_iodata()
      |> IO.iodata_to_binary()

    send_download(conn, {:binary, csv}, filename: "#{deployment_group.name}-device-ids.csv")
  end
end
