defmodule NervesHubWeb.DeviceLiveEditTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHubWeb.Router.Helpers, as: Routes

  alias NervesHubWeb.Endpoint

  describe "validate" do
    test "valid tags allow submit", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))

      assert render_change(view, :validate, params) =~ "new,tags"
    end

    test "invalid tags prevent submit", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: "this is one invalid tag"}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))

      html = render_change(view, :validate, params)
      {:ok, document} = Floki.parse_document(html)

      button_disabled =
        Floki.attribute(document, "button[type=submit]", "disabled") |> Floki.text()

      error_text = Floki.find(document, "span.help-block") |> Floki.text()

      assert button_disabled == "disabled"
      assert error_text == "tags cannot contain spaces"
    end
  end

  describe "save" do
    test "redirects after saving valid tags", %{conn: conn, fixture: fixture} do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = live(conn, device_path(fixture, :edit))
      path = device_path(fixture, :show)
      render_submit(view, :save, params)
      assert_redirect(view, path)
    end
  end

  def device_path(%{device: device, org: org, product: product}, type) do
    Routes.device_path(Endpoint, type, org.name, product.name, device.identifier)
  end
end
