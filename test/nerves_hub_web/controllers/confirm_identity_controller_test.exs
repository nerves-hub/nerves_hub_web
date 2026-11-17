defmodule NervesHubWeb.ConfirmIdentityControllerTest do
  # Not async: Google sign-in is turned on and off through app config.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    Application.put_env(:nerves_hub, :enable_google_auth, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :enable_google_auth, false) end)
  end

  # Signed in as `user`, but not recently.
  defp signed_in(user) do
    init_test_session(build_conn(), %{"user_token" => Accounts.create_user_session_token(user)})
  end

  describe "the page" do
    test "asks an account with a password for it", %{user: user} do
      html = user |> signed_in() |> get(~p"/account/confirm?return_to=/account") |> html_response(200)

      assert html =~ "Confirm it&#39;s you"
      assert html =~ ~s(name="password")
      refute html =~ ~s(value="confirm")
    end

    test "offers Google, and no password, to an account that only signs in with Google" do
      user =
        Fixtures.user_fixture()
        |> Ecto.Changeset.change(google_id: "google-only", password_hash: nil)
        |> Repo.update!()

      html = user |> signed_in() |> get(~p"/account/confirm") |> html_response(200)

      assert html =~ ~s(value="confirm")
      refute html =~ ~s(name="password")
    end
  end

  describe "confirming with a password" do
    test "counts the sign-in as recent and goes back", %{user: user} do
      conn =
        user |> signed_in() |> post(~p"/account/confirm", %{"password" => "test_password", "return_to" => "/account"})

      assert redirected_to(conn) == "/account"
      assert is_integer(get_session(conn, :authenticated_at))
    end

    test "says when the password is wrong", %{user: user} do
      conn = user |> signed_in() |> post(~p"/account/confirm", %{"password" => "not it", "return_to" => "/account"})

      assert html_response(conn, 200) =~ "That password isn&#39;t right."
      refute get_session(conn, :authenticated_at)
    end

    test "only goes back to an account page", %{user: user} do
      for return_to <- ["https://evil.example/account", "//evil.example/account", "/orgs", "/accountx"] do
        conn =
          user |> signed_in() |> post(~p"/account/confirm", %{"password" => "test_password", "return_to" => return_to})

        assert redirected_to(conn) == "/account", "went to #{redirected_to(conn)} for #{return_to}"
      end
    end

    test "five wrong passwords stop a right one for a while", %{user: user} do
      for _ <- 1..5 do
        user |> signed_in() |> post(~p"/account/confirm", %{"password" => "not it"})
      end

      conn = user |> signed_in() |> post(~p"/account/confirm", %{"password" => "test_password"})

      assert html_response(conn, 429) =~ "Too many tries"
      refute get_session(conn, :authenticated_at)
    end
  end

  describe "going to Google" do
    test "connecting needs a recent sign-in first", %{user: user} do
      conn =
        user |> signed_in() |> post(~p"/account/confirm/google", %{"intent" => "connect", "return_to" => "/account"})

      assert redirected_to(conn) == ~p"/account/confirm?#{[return_to: "/account"]}"
      refute get_session(conn, :google_intent)
    end

    test "connecting after a recent sign-in goes to Google for the account's email", %{conn: conn, user: user} do
      conn = post(conn, ~p"/account/confirm/google", %{"intent" => "connect", "return_to" => "/account"})

      assert "/auth/google?" <> query = redirected_to(conn)
      assert %{"prompt" => "select_account", "login_hint" => email} = URI.decode_query(query)
      assert email == user.email
      assert %{"action" => "connect", "user_id" => user_id} = get_session(conn, :google_intent)
      assert user_id == user.id
    end

    test "confirming needs a connected Google account", %{user: user} do
      conn =
        user |> signed_in() |> post(~p"/account/confirm/google", %{"intent" => "confirm", "return_to" => "/account"})

      assert redirected_to(conn) == "/account"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Google sign-in isn't available for your account."
      refute get_session(conn, :google_intent)
    end

    test "isn't offered while this server doesn't offer Google sign-in", %{conn: conn} do
      Application.put_env(:nerves_hub, :enable_google_auth, false)

      conn = post(conn, ~p"/account/confirm/google", %{"intent" => "connect", "return_to" => "/account"})

      assert redirected_to(conn) == "/account"
      refute get_session(conn, :google_intent)
    end
  end

  describe "with two-factor on" do
    setup %{user: user} do
      user = user |> Ecto.Changeset.change(google_id: "google-#{user.id}") |> Repo.update!()
      %{secret: secret} = Fixtures.two_factor_fixture(user)

      %{user: user, secret: secret}
    end

    test "asks for a code along with the password or Google", %{user: user} do
      html = user |> signed_in() |> get(~p"/account/confirm") |> html_response(200)

      assert html =~ ~s(name="code")
      assert html =~ ~s(name="password")
      assert html =~ ~s(value="confirm")
    end

    test "confirms with the password and a code", %{user: user, secret: secret} do
      conn =
        user
        |> signed_in()
        |> post(~p"/account/confirm", %{
          "password" => "test_password",
          "code" => Fixtures.next_totp_code(secret),
          "return_to" => "/account"
        })

      assert redirected_to(conn) == "/account"
      assert is_integer(get_session(conn, :authenticated_at))
    end

    test "won't confirm with the password alone", %{user: user} do
      for code <- [nil, "000000"] do
        params = %{"password" => "test_password", "code" => code, "return_to" => "/account"}
        conn = user |> signed_in() |> post(~p"/account/confirm", params)

        assert html_response(conn, 200) =~ "That code didn&#39;t work."
        refute get_session(conn, :authenticated_at)
      end
    end

    # A browser still signed in to Google would otherwise confirm in one click.
    test "won't go to Google without a code", %{user: user} do
      conn = user |> signed_in() |> post(~p"/account/confirm/google", %{"intent" => "confirm", "code" => "000000"})

      assert html_response(conn, 200) =~ "That code didn&#39;t work."
      refute get_session(conn, :google_intent)
    end

    test "goes to Google with a code", %{user: user, secret: secret} do
      conn =
        user
        |> signed_in()
        |> post(~p"/account/confirm/google", %{
          "intent" => "confirm",
          "code" => Fixtures.next_totp_code(secret),
          "return_to" => "/account"
        })

      assert "/auth/google?" <> _query = redirected_to(conn)
      assert %{"action" => "confirm"} = get_session(conn, :google_intent)
    end
  end

  test "is only for someone signed in" do
    conn = get(build_conn(), ~p"/account/confirm")

    assert redirected_to(conn) =~ "/login"
  end
end
