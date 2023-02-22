defmodule NervesHubAPIWebTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.Accounts

  test "conn missing certificate is rejected" do
    conn = Phoenix.ConnTest.build_conn()
    conn = get(conn, Routes.user_path(conn, :me))
    assert json_response(conn, 403)["status"] == "forbidden"
  end

  test "user certificate last used is updated", %{conn: conn, user: user} do
    [%{last_used: last_used}] = Accounts.get_user_certificates(user)
    get(conn, Routes.user_path(conn, :me))
    [%{last_used: updated_last_used}] = Accounts.get_user_certificates(user)
    assert last_used != updated_last_used
  end
end
