defmodule NervesHubWWWWeb.DeviceLiveIndexTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.Endpoint

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "handle_event" do
    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_index_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{"device-id" => device.id}) =~ "reboot requested"
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{conn: conn, fixture: fixture} do
      %{device: device, user: user} = fixture

      Repo.preload(user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHubWebCore.Accounts.change_org_user_role(&1, :read))

      {:ok, view, _html} = live(conn, device_index_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{"device-id" => device.id}) =~ "reboot blocked"

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end
  end

  def device_index_path(%{org: org, product: product}) do
    Routes.device_path(Endpoint, :index, org.name, product.name)
  end
end
