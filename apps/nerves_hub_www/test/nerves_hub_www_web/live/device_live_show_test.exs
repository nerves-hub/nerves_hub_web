defmodule NervesHubWWWWeb.DeviceLiveShowTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWebCore.{Devices, Repo}
  alias NervesHubWWWWeb.DeviceLive.Show
  alias NervesHubWWWWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{current_org: org, current_user: user} do
    device = Devices.get_devices(org) |> hd
    Endpoint.subscribe("device:#{device.id}")
    [device: device, user: Repo.preload(user, [:org_users])]
  end

  describe "handle_event" do
    test "reboot allowed", session do
      {:ok, view, _html} = mount(Endpoint, Show, session: session)

      before_audit_count = Devices.audit_logs_for(session.device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-requested"
      assert_broadcast("reboot", %{})

      after_audit_count = Devices.audit_logs_for(session.device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", session do
      org_users =
        session.user.org_users
        |> Enum.map(&%{&1 | role: :read})

      user = %{session.user | org_users: org_users}

      {:ok, view, _html} = mount(Endpoint, Show, session: %{session | user: user})

      before_audit_count = Devices.audit_logs_for(session.device) |> length

      assert render_change(view, :reboot, %{}) =~ "reboot-blocked"

      after_audit_count = Devices.audit_logs_for(session.device) |> length

      assert after_audit_count == before_audit_count + 1
    end
  end

  describe "handle_info" do
    test "presence_diff with no change", session do
      payload = %{joins: %{}, leaves: %{}}
      {:ok, view, html} = mount(Endpoint, Show, session: session)

      assert html =~ "offline"
      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})
      assert render(view) =~ "offline"
    end

    test "presence_diff with changes", session do
      payload = %{joins: %{"#{session.device.id}" => %{}}, leaves: %{}}
      {:ok, view, html} = mount(Endpoint, Show, session: session)

      assert html =~ "offline"

      {:ok, device} =
        Devices.update_device(session.device, %{last_communication: DateTime.utc_now()})

      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})

      assert render(view) =~ to_string(device.last_communication)
    end
  end
end
