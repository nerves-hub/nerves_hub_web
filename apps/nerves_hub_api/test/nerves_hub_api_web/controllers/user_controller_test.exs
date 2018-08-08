defmodule NervesHubAPIWeb.UserControllerTest do
  use NervesHubAPIWeb.ConnCase

  test "me", %{conn: conn, user: user} do
    conn = get conn, user_path(conn, :me)
    assert json_response(conn, 200)["data"] == %{
      "name" => user.name,
      "email" => user.email
    }
  end
end
