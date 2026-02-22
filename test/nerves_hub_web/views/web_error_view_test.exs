defmodule NervesHubWeb.WebErrorViewTest do
  use NervesHubWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "render 500.html" do
    assert render_to_string(NervesHubWeb.ErrorHTML, "500", "html", []) =~
             "Sorry, we tried to process your request but things didn't go so well."
  end

  test "render 400.html" do
    assert render_to_string(NervesHubWeb.ErrorHTML, "400", "html", []) =~
             "Sorry, we are unable to process your request as it is invalid or malformed."
  end
end
