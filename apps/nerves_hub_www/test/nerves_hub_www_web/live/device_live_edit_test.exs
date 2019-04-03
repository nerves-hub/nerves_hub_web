defmodule NervesHubWWWWeb.DeviceLiveEditTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.Devices
  alias NervesHubWWWWeb.DeviceLive.Edit
  alias NervesHubWWWWeb.Endpoint

  describe "validate" do
    test "valid tags allow submit", %{current_org: org} do
      params = %{"device" => %{tags: "new,tags"}}
      device = Devices.get_devices(org) |> hd
      changeset = Devices.Device.changeset(device, %{})

      {:ok, view, _html} = mount(Endpoint, Edit, session: %{device: device, changeset: changeset})

      assert render_change(view, :validate, params) =~ "new,tags"
    end

    test "invalid tags prevent submit", %{current_org: org} do
      params = %{"device" => %{tags: "this is one invalid tag"}}
      device = Devices.get_devices(org) |> hd
      changeset = Devices.Device.changeset(device, %{})

      {:ok, view, _html} = mount(Endpoint, Edit, session: %{device: device, changeset: changeset})

      html = render_change(view, :validate, params)
      button_disabled = Floki.attribute(html, "button[type=submit]", "disabled") |> Floki.text()
      error_text = Floki.find(html, "span.help-block") |> Floki.text()

      assert button_disabled == "disabled"
      assert error_text == "tags cannot contain spaces"
    end
  end

  describe "save" do
    test "redirects after saving valid tags", %{current_org: org} do
      params = %{"device" => %{tags: "new,tags"}}
      device = Devices.get_devices(org) |> hd
      changeset = Devices.Device.changeset(device, %{})

      {:ok, view, _html} = mount(Endpoint, Edit, session: %{device: device, changeset: changeset})
      device_path = "/devices/#{device.id}"

      assert_redirect(view, ^device_path, fn ->
        assert render_submit(view, :save, params)
      end)
    end
  end
end
