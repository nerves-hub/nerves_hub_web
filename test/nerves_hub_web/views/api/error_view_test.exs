defmodule NervesHubWeb.API.ErrorJSONTest do
  @moduledoc false
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHubWeb.API.ErrorJSON

  @message "Resource Not Found or Authorization Insufficient"

  test "renders 401.json" do
    assert ErrorJSON.render("401.json", %{}) == %{errors: %{detail: @message}}
  end

  test "renders 404.json" do
    assert ErrorJSON.render("404.json", %{}) == %{errors: %{detail: @message}}
  end

  test "renders 500.json" do
    assert ErrorJSON.render("500.json", %{}) == %{errors: %{detail: "Internal Server Error"}}
  end
end
