defmodule NervesHubWWWWeb.DeviceLiveEditTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWWWWeb.Router.Helpers, as: Routes

  alias NervesHubWWWWeb.DeviceLive.{Show, Edit}
  alias NervesHubWWWWeb.Endpoint

  setup %{conn: conn, fixture: %{device: device, product: product}} do
    # TODO: Use Plug.Conn.get_session/1 when upgraded to Plug >= 1.8
    session =
      conn.private.plug_session
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:path_params, %{"product_id" => product.id, "id" => device.id})

    [session: session]
  end

  describe "validate" do
    test "valid tags allow submit", %{session: session} do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = mount(Endpoint, Edit, session: session)

      assert render_change(view, :validate, params) =~ "new,tags"
    end

    test "invalid tags prevent submit", %{session: session} do
      params = %{"device" => %{tags: "this is one invalid tag"}}

      {:ok, view, _html} = mount(Endpoint, Edit, session: session)

      html = render_change(view, :validate, params)
      button_disabled = Floki.attribute(html, "button[type=submit]", "disabled") |> Floki.text()
      error_text = Floki.find(html, "span.help-block") |> Floki.text()

      assert button_disabled == "disabled"
      assert error_text == "tags cannot contain spaces"
    end
  end

  describe "save" do
    test "redirects after saving valid tags", %{
      fixture: %{device: device, product: product},
      session: session
    } do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = mount(Endpoint, Edit, session: session)
      path = Routes.product_device_path(Endpoint, Show, product.id, device.id)

      assert_redirect(view, ^path, fn ->
        assert render_submit(view, :save, params)
      end)
    end
  end
end
