defmodule NervesHubWeb.Plugs.TimezoneTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias NervesHubWeb.Plugs.Timezone

  @session Plug.Session.init(store: :cookie, key: "_tz_test", signing_salt: "salt")

  defp call(cookie) do
    :get
    |> conn("/")
    |> then(fn conn -> if cookie, do: put_req_cookie(conn, "time_zone", cookie), else: conn end)
    |> Plug.Session.call(@session)
    |> fetch_session()
    |> Timezone.call(Timezone.init([]))
  end

  test "copies a recognised zone into the session" do
    assert get_session(call("Pacific/Auckland"), "time_zone") == "Pacific/Auckland"
  end

  test "ignores a cookie the time zone database doesn't recognise" do
    assert get_session(call("Mars/Olympus_Mons"), "time_zone") == nil
  end

  test "does nothing when the cookie is absent" do
    assert get_session(call(nil), "time_zone") == nil
  end
end
