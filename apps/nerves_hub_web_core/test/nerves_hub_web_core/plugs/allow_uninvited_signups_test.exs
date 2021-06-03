defmodule NervesHubWebCore.Plugs.AllowUninvitedSignupsTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn

  describe "web" do
    setup do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> fetch_flash
        |> bypass_through(NervesHubWWWWeb.Router)
        |> dispatch(NervesHubWWWWeb.Endpoint, :get, "/")

      %{conn: conn}
    end

    test "user is redirected when signups are disabled", %{conn: conn} do
      Application.put_env(:nerves_hub_web_core, :allow_signups, false)
      conn = NervesHubWebCore.Plugs.AllowUninvitedSignups.call(conn, [])

      assert redirected_to(conn) == "/"

      assert get_session(conn, :phoenix_flash) == %{
               "error" => "Sorry signups are not enabled at this time."
             }
    end

    test "user is not redirected when signups are enabled", %{conn: conn} do
      Application.put_env(:nerves_hub_web_core, :allow_signups, true)
      conn_through = NervesHubWebCore.Plugs.AllowUninvitedSignups.call(conn, [])

      assert conn_through.status != 302
      assert conn_through == conn
    end
  end

  describe "api" do
    setup do
      conn =
        build_conn()
        |> bypass_through(NervesHubAPIWeb.Router)
        |> dispatch(NervesHubAPIWeb.Endpoint, :post, "/users/register")

      %{conn: conn}
    end

    test "fails registration when signups are disabled", %{conn: conn} do
      Application.put_env(:nerves_hub_web_core, :allow_signups, false)
      conn = NervesHubWebCore.Plugs.AllowUninvitedSignups.call(conn, [])

      assert json_response(conn, 403) == %{
               "status" => "Public signups disabled. Invite required to signup"
             }
    end

    test "passes conn when signups are allowed", %{conn: conn} do
      Application.put_env(:nerves_hub_web_core, :allow_signups, true)
      conn_through = NervesHubWebCore.Plugs.AllowUninvitedSignups.call(conn, [])

      assert conn_through == conn
    end
  end
end
