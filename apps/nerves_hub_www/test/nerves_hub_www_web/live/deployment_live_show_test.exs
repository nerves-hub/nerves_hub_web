defmodule NervesHubWWWWeb.DeploymentLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.{DeploymentLive.Show, Endpoint}

  setup %{fixture: fixture} do
    [
      deployment: Repo.preload(fixture.deployment, :firmware),
      product: fixture.product,
      user: fixture.user
    ]
  end

  describe "handle_event" do
    test "toggle active", session do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(session.deployment) |> length

      assert render_click(view, :toggle_active, "true") =~ "Make Inactive"
      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(session.deployment)

      assert deployment.is_active == true

      after_audit_count = AuditLogs.logs_for(session.deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "toggle inactive", session do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(session.deployment) |> length

      assert render_click(view, :toggle_active, "false") =~ "Make Active"
      # assert_broadcast("reboot", %{})

      deployment = Repo.reload(session.deployment)

      assert deployment.is_active == false

      after_audit_count = AuditLogs.logs_for(session.deployment) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "delete", session do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      products_path = "/products/#{session.product.id}/deployments"

      assert_redirect(view, ^products_path, fn ->
        assert render_submit(view, :delete)
      end)

      [audit_log | _tail] = AuditLogs.logs_for(session.deployment)

      assert audit_log.action == :delete

      assert audit_log.params == %{
               "id" => session.deployment.id,
               "name" => session.deployment.name
             }
    end
  end
end
