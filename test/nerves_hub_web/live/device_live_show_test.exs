defmodule NervesHubWeb.DeviceLiveShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHub.{AuditLogs, Repo}
  alias NervesHubWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "handle_event" do
    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      _view = render_change(view, :reboot, %{})
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{conn: conn, fixture: fixture} do
      %{device: device, user: user} = fixture

      Repo.preload(user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHub.Accounts.change_org_user_role(&1, :read))

      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      _view = render_change(view, :reboot, %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end
  end

  describe "handle_info" do
    test "presence_diff with no change", %{conn: conn, fixture: fixture} do
      payload = %{joins: %{}, leaves: %{}}
      {:ok, view, html} = live(conn, device_show_path(fixture))

      assert html =~ "offline"
      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})
      assert render(view) =~ "offline"
    end

    test "presence_diff with changes", %{conn: conn, fixture: fixture} do
      {:ok, view, html} = live(conn, device_show_path(fixture))

      assert html =~ "offline"

      send(view.pid, %Broadcast{event: "connection_change", payload: %{status: "online"}})

      assert render(view) =~ "online"
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    Routes.device_path(Endpoint, :show, org.name, product.name, device.identifier)
  end
end
