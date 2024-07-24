defmodule NervesHubWeb.API.ErrorViewTest do
  use NervesHubWeb.APIConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "renders 401.json" do
    assert render(NervesHubWeb.API.ErrorView, "401.json", []) == %{
             errors: %{detail: "Not Authenticated"}
           }
  end

  test "renders 404.json" do
    assert render(NervesHubWeb.API.ErrorView, "404.json", []) == %{
             errors: %{detail: "Resource Not Found or Authorization Insufficient"}
           }
  end

  test "renders 500.json" do
    assert render(NervesHubWeb.API.ErrorView, "500.json", []) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
