defmodule NervesHubWWWWeb.DeviceLiveEditTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWWWWeb.Router.Helpers, as: Routes

  alias NervesHubWWWWeb.Endpoint

  test "redirects on mount with unrecognized session structure", %{conn: conn, fixture: fixture} do
    home_path = Routes.home_path(Endpoint, :index)
    conn = clear_session(conn)
    assert {:error, %{redirect: %{to: ^home_path}}} = live(conn, device_path(fixture, :edit))
  end

  describe "validate" do
    test "valid tags allow submit", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))

      assert render_change(view, :validate, params) =~ "new,tags"
    end

    test "invalid tags prevent submit", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: " "}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))

      html = render_change(view, :validate, params)
      button_disabled = Floki.attribute(html, "button[type=submit]", "disabled") |> Floki.text()
      error_text = Floki.find(html, "span.help-block") |> Floki.text()

      assert button_disabled == "disabled"
      assert error_text == "should have at least 1 item(s)"
    end
  end

  describe "save" do
    test "redirects after saving valid tags", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))
      path = device_path(fixture, :show)

      assert_redirect(view, ^path, fn ->
        assert render_submit(view, :save, params)
      end)
    end
  end

  def device_path(%{device: device, org: org, product: product}, type) do
    Routes.device_path(Endpoint, type, org.name, product.name, device.identifier)
  end
end
