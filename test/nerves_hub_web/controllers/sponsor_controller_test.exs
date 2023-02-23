defmodule NervesHubWeb.SponsorControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  test "renders sponsors", %{
    conn: conn
  } do
    conn = get(conn, Routes.sponsor_path(conn, :index))
    assert html_response(conn, 200) =~ "Sponsors"
  end
end
