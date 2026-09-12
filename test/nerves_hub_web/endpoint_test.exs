defmodule NervesHubWeb.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias NervesHubWeb.Endpoint

  # Another NervesHub on a sibling host can scope its cookie to a shared parent
  # domain, and the browser then sends it here too -- first, if it is older.
  @foreign "_nerves_hub_key=SFMyNTY.set-by-another-instance"

  setup do
    previous = Application.get_env(:nerves_hub, :session_cookie_key)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:nerves_hub, :session_cookie_key)
        value -> Application.put_env(:nerves_hub, :session_cookie_key, value)
      end
    end)
  end

  describe "session_cookie_key/0" do
    test "defaults to _nerves_hub_key" do
      Application.delete_env(:nerves_hub, :session_cookie_key)

      assert Endpoint.session_cookie_key() == "_nerves_hub_key"
      assert Endpoint.session_options()[:key] == "_nerves_hub_key"
    end

    test "is taken from configuration" do
      Application.put_env(:nerves_hub, :session_cookie_key, "_nerves_hub_qa_key")

      assert Endpoint.session_cookie_key() == "_nerves_hub_qa_key"
      assert Endpoint.session_options()[:key] == "_nerves_hub_qa_key"
    end
  end

  describe "a foreign cookie sent ahead of this instance's" do
    test "displaces the session when both share the default name" do
      Application.delete_env(:nerves_hub, :session_cookie_key)
      ours = session_cookie_for("user_token", "ours")

      conn = request_with_cookies("#{@foreign}; #{ours}")

      # The server reads the first cookie of that name, cannot decrypt it, and
      # carries on with no session. That is what fails every form's CSRF check.
      assert get_session(conn, "user_token") == nil
    end

    test "is ignored when this instance uses its own name" do
      Application.put_env(:nerves_hub, :session_cookie_key, "_nerves_hub_qa_key")
      ours = session_cookie_for("user_token", "ours")

      conn = request_with_cookies("#{@foreign}; #{ours}")

      assert get_session(conn, "user_token") == "ours"
    end
  end

  defp request_with_cookies(header) do
    :get
    |> conn("/")
    |> put_req_header("cookie", header)
    |> with_session()
  end

  defp session_cookie_for(key, value) do
    conn =
      :get
      |> conn("/")
      |> with_session()
      |> put_session(key, value)
      |> send_resp(200, "")

    name = Endpoint.session_cookie_key()
    "#{name}=#{conn.resp_cookies[name].value}"
  end

  defp with_session(conn) do
    %{conn | secret_key_base: String.duplicate("a", 64)}
    |> Plug.Session.call(Plug.Session.init(Endpoint.session_options()))
    |> fetch_session()
  end
end
