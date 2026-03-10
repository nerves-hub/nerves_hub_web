defmodule NervesHubWeb.API.ErrorJSONTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHubWeb.API.ErrorJSON

  test "renders 401.json" do
    assert ErrorJSON.render("401.json", %{}) == %{
             errors: %{detail: "Resource Not Found or Authorization Insufficient"}
           }
  end

  test "renders 404.json" do
    assert ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Resource Not Found or Authorization Insufficient"}
           }
  end

  test "renders 500.json" do
    assert ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Sorry, an unexpected error occurred. The masters of the web have been notified."}}
  end
end
