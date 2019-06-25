defmodule NervesHubWWWWeb.DeploymentLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.{DeploymentLive.Show, Endpoint}

  setup %{conn: conn, fixture: fixture} do
    %{org: org, deployment: deployment, product: product} = fixture
    # TODO: Use Plug.Conn.get_session/1 when upgraded to Plug >= 1.8
    session =
      conn.private.plug_session
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:org_id, org.id)
      |> Map.put(:product_id, product.id)
      |> Map.put(:deployment_id, deployment.id)

    [session: session]
  end

  describe "handle_event" do
    test "toggle active", %{fixture: %{deployment: deployment}, session: session} do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(deployment) |> length

      assert render_click(view, :toggle_active, "true") =~ "Make Inactive"
      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(deployment)

      assert deployment.is_active == true

      after_audit_count = AuditLogs.logs_for(deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "toggle inactive", %{fixture: %{deployment: deployment}, session: session} do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(deployment) |> length

      assert render_click(view, :toggle_active, "false") =~ "Make Active"
      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(deployment)

      assert deployment.is_active == false

      after_audit_count = AuditLogs.logs_for(deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "delete", %{
      fixture: %{org: org, deployment: deployment, product: product},
      session: session
    } do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      path = Routes.deployment_path(Endpoint, :index, org.name, product.name)

      assert_redirect(view, ^path, fn ->
        assert render_submit(view, :delete)
      end)

      [audit_log | _tail] = AuditLogs.logs_for(deployment)

      assert audit_log.action == :delete

      assert audit_log.params == %{
               "id" => deployment.id,
               "name" => deployment.name
             }
    end
  end
end
