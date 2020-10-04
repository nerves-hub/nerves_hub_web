defmodule NervesHubWWWWeb.DeviceLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "redirects on mount with unrecognized session structure", %{conn: conn, fixture: fixture} do
    home_path = Routes.home_path(Endpoint, :index)
    conn = clear_session(conn)

    assert {:error, {:redirect, %{flash: _flash, to: ^home_path}}} =
             live(conn, device_show_path(fixture))
  end

  describe "handle_event" do
    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-requested"
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{conn: conn, fixture: fixture} do
      %{device: device, user: user} = fixture

      Repo.preload(user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHubWebCore.Accounts.change_org_user_role(&1, :read))

      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-blocked"

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
      %{device: device} = fixture
      payload = %{joins: %{"#{device.id}" => %{status: "online"}}, leaves: %{}}
      {:ok, view, html} = live(conn, device_show_path(fixture))

      assert html =~ "offline"

      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})

      assert render(view) =~ "online"
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    Routes.device_path(Endpoint, :show, org.name, product.name, device.identifier)
  end
end
