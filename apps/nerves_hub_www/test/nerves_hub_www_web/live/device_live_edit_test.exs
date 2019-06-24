defmodule NervesHubWWWWeb.DeviceLiveEditTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWWWWeb.Router.Helpers, as: Routes

  alias NervesHubWWWWeb.DeviceLive.Edit
  alias NervesHubWWWWeb.Endpoint

  setup %{conn: conn, fixture: %{org: org, device: device, product: product}} do
    # TODO: Use Plug.Conn.get_session/1 when upgraded to Plug >= 1.8
    session =
      conn.private.plug_session
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:org_id, org.id)
      |> Map.put(:product_id, product.id)
      |> Map.put(:device_id, device.id)

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
      fixture: %{org: org, device: device, product: product},
      session: session
    } do
      params = %{"device" => %{tags: "new,tags"}}

      {:ok, view, _html} = mount(Endpoint, Edit, session: session)
      path = Routes.device_path(Endpoint, :show, org.name, product.name, device.identifier)

      assert_redirect(view, ^path, fn ->
        assert render_submit(view, :save, params)
      end)
    end
  end
end
