defmodule NervesHubWeb.DeploymentGroupControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Repo

  describe "export_audit_logs" do
    test "redirects when no audit logs exist", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      Repo.delete_all(AuditLog)

      conn =
        get(
          conn,
          ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group.name}/audit_logs/download"
        )

      assert redirected_to(conn) =~
               "/org/#{org.name}/#{product.name}/deployment_groups"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "No audit logs exist"
    end

    test "downloads CSV when audit logs exist", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      deployment_group: deployment_group
    } do
      AuditLogs.audit!(user, deployment_group, "test action")

      conn =
        get(
          conn,
          ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group.name}/audit_logs/download"
        )

      assert response_content_type(conn, :csv) =~ "text/csv"
    end
  end
end
