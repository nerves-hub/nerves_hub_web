defmodule NervesHubWeb.ErrorViewTest do
  use NervesHubWeb.ConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "render 500.html" do
    assert render_to_string(NervesHubWeb.ErrorView, "500.html", []) =~
             "Sorry, we tried to process your request but things didn't go so well."
  end
end
