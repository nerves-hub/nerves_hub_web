defmodule NervesHubWWWWeb.SponsorControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  test "renders sponsors", %{
    conn: conn
  } do
    conn = get(conn, sponsor_path(conn, :index))
    assert html_response(conn, 200) =~ "Sponsors"
  end
end
