defmodule NervesHubWWWWeb.DeviceLiveConsoleTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWebCore.Devices
  alias NervesHubWWWWeb.{DeviceLive.Console, Endpoint}
  alias NervesHubDevice.Presence

  alias Phoenix.Socket.Broadcast

  setup %{current_org: org, current_user: user} = context do
    device = Devices.get_devices(org) |> hd
    Endpoint.subscribe("console:#{device.id}")

    unless context[:skip_presence] do
      Presence.track(self(), "devices:#{device.org_id}", device.id, %{console_available: true})
    end

    [device: device, user: user, username: user.username, user_role: :admin]
  end

  describe "mount" do
    test "successful mount init IEx server on device", session do
      {:ok, _view, _html} = mount(Endpoint, Console, session: session)
      assert_broadcast("init", %{})
    end

    @tag skip_presence: true
    test "redirects when device not configured for remote IEx", session do
      {:error, %{redirect: somewhere}} = mount(Endpoint, Console, session: session)
      refute_broadcast("init", %{})
      assert somewhere == "/devices/#{session.device.id}"
    end
  end

  describe "handle_event" do
    test "iex_submit", session do
      {:ok, view, _html} = mount(Endpoint, Console, session: session)
      input = "Howdy"
      iex_line = "iex (#{session.username})&gt; #{input}"

      assert render_submit(view, :iex_submit, %{iex_input: input}) =~ iex_line

      assert_broadcast("add_line", %{data: iex_line})
      assert_broadcast("io_reply", %{data: input, kind: "get_line"})
    end

    test "iex_submit - clear text", session do
      {:ok, view, _html} = mount(Endpoint, Console, session: session)

      refute render_submit(view, :iex_submit, %{iex_input: "clear"}) =~ "NervesHub IEx Live"
    end
  end

  describe "handle_info" do
    test "put_chars", session do
      {:ok, view, html} = mount(Endpoint, Console, session: session)

      refute html =~ "Howdy"

      msg = %Broadcast{event: "put_chars", payload: %{"data" => "Howdy"}}
      send(view.pid, msg)

      assert render(view) =~ "Howdy"
    end

    test "get_line", session do
      {:ok, view, html} = mount(Endpoint, Console, session: session)

      refute html =~ "Howdy"

      msg = %Broadcast{event: "get_line", payload: %{"data" => "iex(1)>"}}
      send(view.pid, msg)

      assert render(view) =~ "iex(#{session.username})&gt;"
    end

    test "add_line", session do
      {:ok, view, html} = mount(Endpoint, Console, session: session)

      refute html =~ "Howdy"

      msg = %Broadcast{event: "add_line", payload: %{data: "wat it do?"}}
      send(view.pid, msg)

      assert render(view) =~ "wat it do?"
    end
  end
end
