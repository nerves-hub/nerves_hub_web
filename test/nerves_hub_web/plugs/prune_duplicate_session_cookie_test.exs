defmodule NervesHubWeb.Plugs.PruneDuplicateSessionCookieTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias NervesHubWeb.Plugs.PruneDuplicateSessionCookie

  @cookie "_nerves_hub_key"

  defp with_cookie(header) do
    :get
    |> conn("/")
    |> put_req_header("cookie", header)
    |> PruneDuplicateSessionCookie.call([])
  end

  defp set_cookies(conn), do: get_resp_header(conn, "set-cookie")

  describe "with :session_cookie_domain configured" do
    setup do
      previous = Application.get_env(:nerves_hub, :session_cookie_domain)
      Application.put_env(:nerves_hub, :session_cookie_domain, ".example.com")

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:nerves_hub, :session_cookie_domain)
          value -> Application.put_env(:nerves_hub, :session_cookie_domain, value)
        end
      end)
    end

    test "emits a host-only deletion when a duplicate cookie is present" do
      conn = with_cookie("#{@cookie}=aaa; other=1; #{@cookie}=bbb")

      assert [set_cookie] = set_cookies(conn)
      # Host-only (no Domain) + expired => deletes only the stale host-only variant.
      assert set_cookie =~ "#{@cookie}=;"
      assert set_cookie =~ "max-age=0"
      refute set_cookie =~ "domain="
    end

    test "does nothing when only one session cookie is present" do
      assert set_cookies(with_cookie("#{@cookie}=aaa; other=1")) == []
    end

    test "does nothing when there is no session cookie" do
      assert set_cookies(with_cookie("other=1; another=2")) == []
    end
  end

  test "does nothing when :session_cookie_domain is not configured" do
    previous = Application.get_env(:nerves_hub, :session_cookie_domain)
    Application.delete_env(:nerves_hub, :session_cookie_domain)

    on_exit(fn ->
      if previous, do: Application.put_env(:nerves_hub, :session_cookie_domain, previous)
    end)

    # A duplicate is present, but without a shared domain a host-only cookie is the
    # real session — never touch it.
    assert set_cookies(with_cookie("#{@cookie}=aaa; #{@cookie}=bbb")) == []
  end
end
