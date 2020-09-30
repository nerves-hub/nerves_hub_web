defmodule NervesHubWWWWeb.DeploymentLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.Endpoint

  test "redirects on mount with unrecognized session structure", %{fixture: fixture, conn: conn} do
    home_path = Routes.home_path(Endpoint, :index)
    conn = clear_session(conn)
    assert {:error, {:redirect, %{flash: _flash, to: ^home_path}}} = live(conn, deployment_path(fixture, :show))
  end

  describe "handle_event" do
    test "toggle active", %{fixture: fixture, conn: conn} do
      %{deployment: deployment} = fixture
      {:ok, view, _html} = live(conn, deployment_path(fixture, :show))

      before_audit_count = AuditLogs.logs_for(deployment) |> length

      assert render_click(view, :toggle_active, %{"isactive" => "true"}) =~ "Turn Off"

      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(deployment)

      assert deployment.is_active == true

      after_audit_count = AuditLogs.logs_for(deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "toggle inactive", %{fixture: fixture, conn: conn} do
      %{deployment: deployment} = fixture
      {:ok, view, _html} = live(conn, deployment_path(fixture, :show))

      before_audit_count = AuditLogs.logs_for(deployment) |> length

      assert render_click(view, :toggle_active, %{"isactive" => "false"}) =~ "Turn On"

      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(deployment)

      assert deployment.is_active == false

      after_audit_count = AuditLogs.logs_for(deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "delete", %{fixture: fixture, conn: conn} do
      %{org: org, deployment: deployment, product: product} = fixture

      {:ok, view, _html} = live(conn, deployment_path(fixture, :show))

      path = Routes.deployment_path(Endpoint, :index, org.name, product.name)
      render_submit(view, :delete)
      assert_redirect(view, path)

      [audit_log | _tail] = AuditLogs.logs_for(deployment)

      assert audit_log.action == :delete

      assert audit_log.params == %{
               "id" => deployment.id,
               "name" => deployment.name
             }
    end
  end

  def deployment_path(%{deployment: deployment, org: org, product: product}, type) do
    Routes.deployment_path(Endpoint, type, org.name, product.name, deployment.name)
  end
end
