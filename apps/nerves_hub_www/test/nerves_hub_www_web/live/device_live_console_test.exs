defmodule NervesHubWWWWeb.DeviceLiveConsoleTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHubWWWWeb.Router.Helpers, as: Routes
  alias NervesHubWWWWeb.Endpoint
  alias NervesHubDevice.Presence

  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device, product: product}} = context do
    Endpoint.subscribe("console:#{device.id}")

    unless context[:skip_presence] do
      Presence.track(self(), "product:#{product.id}:devices", device.id, %{
        console_available: true
      })
    end

    :ok
  end

  describe "mount" do
    test "successful mount init IEx server on device", %{conn: conn, fixture: fixture} do
      {:ok, _view, _html} = live(conn, device_path(fixture, :console))
      assert_broadcast("init", %{})
    end

    @tag skip_presence: true
    test "redirects when device not configured for remote IEx", %{conn: conn, fixture: fixture} do
      path = device_path(fixture, :show)
      assert {:error, %{redirect: %{to: ^path}}} = live(conn, device_path(fixture, :console))
      refute_broadcast("init", %{})
    end

    test "redirects on mount with unrecognized session structure", %{conn: conn, fixture: fixture} do
      home_path = Routes.home_path(Endpoint, :index)
      conn = clear_session(conn)

      assert {:error, %{redirect: %{to: ^home_path}}} = live(conn, device_path(fixture, :console))
    end
  end

  describe "handle_event" do
    test "iex_submit", %{conn: conn, fixture: fixture} do
      {:ok, view, _html} = live(conn, device_path(fixture, :console))
      input = "Howdy"
      iex_line = "iex(#{fixture.user.username})&gt; #{input}"

      assert render_submit(view, :iex_submit, %{iex_input: input}) =~ iex_line

      assert_broadcast("add_line", %{data: iex_line})
      assert_broadcast("io_reply", %{data: input, kind: "get_line"})
    end

    test "iex_submit - clear text", %{conn: conn, fixture: fixture} do
      {:ok, view, _html} = live(conn, device_path(fixture, :console))

      refute render_submit(view, :iex_submit, %{iex_input: "clear"}) =~ "NervesHub IEx Live"
    end
  end

  describe "handle_info" do
    test "put_chars", %{conn: conn, fixture: fixture} do
      {:ok, view, html} = live(conn, device_path(fixture, :console))

      refute html =~ "Howdy"

      msg = %Broadcast{event: "put_chars", payload: %{"data" => "Howdy"}}
      send(view.pid, msg)

      assert render(view) =~ "Howdy"
    end

    test "put_chars with binary list", %{conn: conn, fixture: fixture} do
      list_line = [72, 111, 119, 100, 121, 32, 'Partner']

      {:ok, view, html} = live(conn, device_path(fixture, :console))

      refute html =~ "Howdy Partner"

      msg = %Broadcast{event: "put_chars", payload: %{"data" => list_line}}
      send(view.pid, msg)

      assert render(view) =~ "Howdy Partner"
    end

    test "get_line", %{conn: conn, fixture: fixture} do
      {:ok, view, html} = live(conn, device_path(fixture, :console))

      refute html =~ "Howdy"

      msg = %Broadcast{event: "get_line", payload: %{"data" => "iex(1)>"}}
      send(view.pid, msg)

      assert render(view) =~ "iex(#{fixture.user.username})&gt;"
    end

    test "add_line", %{conn: conn, fixture: fixture} do
      {:ok, view, html} = live(conn, device_path(fixture, :console))

      refute html =~ "Howdy"

      msg = %Broadcast{event: "add_line", payload: %{data: "wat it do?"}}
      send(view.pid, msg)

      assert render(view) =~ "wat it do?"
    end
  end

  def device_path(%{device: device, org: org, product: product}, type) do
    Routes.device_path(Endpoint, type, org.name, product.name, device.identifier)
  end
end
