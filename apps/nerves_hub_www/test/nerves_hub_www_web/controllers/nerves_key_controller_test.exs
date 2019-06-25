defmodule NervesHubWWWWeb.NervesKeyControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  test "renders nerves_key", %{
    conn: conn
  } do
    conn = get(conn, Routes.nerves_key_path(conn, :index))
    assert html_response(conn, 302) =~ "https://github.com/nerves-hub/nerves_key"
  end
end
