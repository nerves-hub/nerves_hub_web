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

    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s[attachment; filename="#{deployment_group.name}-device-ids.csv"]
      )
      |> send_chunked(:ok)

    {:ok, conn} = chunk(conn, CSV.dump_to_iodata([["identifier"]]))

    {:ok, conn} =
      ManagedDeployments.device_identifiers_reducer(deployment_group, conn, fn conn, identifier ->
        chunk(conn, CSV.dump_to_iodata([[identifier]]))
      end)

    conn
  end
end
