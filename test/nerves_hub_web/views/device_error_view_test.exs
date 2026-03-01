defmodule NervesHubWeb.DeviceErrorViewTest do
  use NervesHubWeb.DeviceConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "render 500.html" do
    assert render_to_string(NervesHubWeb.ErrorDeviceHTML, "500", "html", []) =~
             "Sorry, we tried to process your request but something went wrong."
  end

  test "render 400.html" do
    assert render_to_string(NervesHubWeb.ErrorDeviceHTML, "400", "html", []) =~
             "Sorry, your request was invalid or corrupted."
  end
end
