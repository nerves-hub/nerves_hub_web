defmodule NervesHubWWWWeb.DeviceLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWebCore.{AuditLogs, Repo}
  alias NervesHubWWWWeb.DeviceLive.Show
  alias NervesHubWWWWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{conn: conn, fixture: %{device: device}} do
    # TODO: Use Plug.Conn.get_session/1 when upgraded to Plug >= 1.8
    session =
      conn.private.plug_session
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:path_params, %{"id" => device.id})

    Endpoint.subscribe("device:#{device.id}")
    [session: session]
  end

  describe "handle_event" do
    test "reboot allowed", %{fixture: %{device: device}, session: session} do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-requested"
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{fixture: %{device: device, user: user}, session: session} do
      Repo.preload(user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHubWebCore.Accounts.change_org_user_role(&1, :read))

      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-blocked"

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end
  end

  describe "handle_info" do
    test "presence_diff with no change", %{session: session} do
      payload = %{joins: %{}, leaves: %{}}
      {:ok, view, html} = mount(Endpoint, Show, session: session)

      assert html =~ "offline"
      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})
      assert render(view) =~ "offline"
    end

    test "presence_diff with changes", %{fixture: %{device: device}, session: session} do
      payload = %{joins: %{"#{device.id}" => %{status: "online"}}, leaves: %{}}
      {:ok, view, html} = mount(Endpoint, Show, session: session)

      assert html =~ "offline"

      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})

      assert render(view) =~ "online"
    end
  end
end
