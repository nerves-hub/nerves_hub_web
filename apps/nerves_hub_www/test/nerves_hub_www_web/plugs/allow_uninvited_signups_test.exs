defmodule NervesHubWWWWeb.Plugs.AllowUninvitedSignupsTest do
  use NervesHubWWWWeb.ConnCase.Browser
  use Plug.Test

  test "user is redirected when signups are disabled", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> fetch_flash
      |> NervesHubWWWWeb.Plugs.AllowUninvitedSignups.call(allow_uninvited: false)

    assert redirected_to(conn) == "/"

    assert get_session(conn, :phoenix_flash) == %{
             "error" => "Sorry signups are not enabled at this time."
           }
  end

  test "user is not redirected when signups are enabled", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> fetch_flash
      |> NervesHubWWWWeb.Plugs.AllowUninvitedSignups.call(allow_uninvited: true)

    assert conn.status != 302
  end
end
