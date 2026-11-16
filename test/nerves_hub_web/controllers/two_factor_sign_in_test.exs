defmodule NervesHubWeb.TwoFactorSignInTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  @password "JohnRingoPaulGeorge"

  setup do
    user = Fixtures.user_fixture(%{name: "Sgt Pepper", email: "sgtpepper@geocities.com", password: @password})
    Fixtures.org_fixture(user, %{name: "LonelyHeartsClubBand"})

    Map.put(Fixtures.two_factor_fixture(user), :user, user)
  end

  defp sign_in_with_password(conn \\ build_conn(), path \\ ~p"/login") do
    conn
    |> visit(path)
    |> fill_in("Email", with: "sgtpepper@geocities.com")
    |> fill_in("Password", with: @password)
    |> submit()
  end

  test "asks for a code after the password, then signs in", %{secret: secret} do
    sign_in_with_password()
    |> assert_path(~p"/login/two-factor")
    |> assert_has("#two_factor_account", text: "sgtpepper@geocities.com")
    |> fill_in("Authentication code", with: Fixtures.next_totp_code(secret))
    |> click_button("Verify")
    |> assert_path(~p"/orgs")
    |> assert_has("div", text: "Welcome back!")
  end

  test "isn't signed in until the code is right" do
    sign_in_with_password()
    |> assert_path(~p"/login/two-factor")
    |> visit(~p"/orgs")
    |> assert_path(~p"/login")
  end

  test "a wrong code says so and stays on the page" do
    sign_in_with_password()
    |> fill_in("Authentication code", with: "000000")
    |> click_button("Verify")
    |> assert_has("[role='alert']", text: "That code didn't work")
    |> visit(~p"/orgs")
    |> assert_path(~p"/login")
  end

  test "a recovery code signs in and says how many are left", %{recovery_codes: [code | _]} do
    sign_in_with_password()
    |> click_link("Use a recovery code instead")
    |> fill_in("Recovery code", with: code)
    |> click_button("Verify")
    |> assert_path(~p"/orgs")
    |> assert_has("div", text: "You signed in with a recovery code. You have 9 left.")
  end

  test "a wrong recovery code keeps the recovery code field open" do
    sign_in_with_password()
    |> click_link("Use a recovery code instead")
    |> fill_in("Recovery code", with: "aaaaa-aaaaa")
    |> click_button("Verify")
    |> assert_has("[role='alert']", text: "Check it against the codes you saved")
    |> assert_has("#two_factor_recovery:not([hidden]) #recovery_code:not([disabled])")
    |> assert_has("#two_factor_app[hidden] #code[disabled]")
    |> click_link("Use your authenticator app")
    |> assert_has("#two_factor_app:not([hidden]) #code:not([disabled])")
  end

  test "the code field takes a recovery code too, for a browser without JavaScript", %{recovery_codes: [code | _]} do
    sign_in_with_password()
    |> fill_in("Authentication code", with: code)
    |> click_button("Verify")
    |> assert_path(~p"/orgs")
  end

  test "goes back to where the user was heading", %{secret: secret} do
    sign_in_with_password(build_conn(), ~p"/orgs/new")
    |> assert_path(~p"/login/two-factor")
    |> fill_in("Authentication code", with: Fixtures.next_totp_code(secret))
    |> click_button("Verify")
    |> assert_path(~p"/orgs/new")
  end

  test "five wrong codes lock the step for a while", %{secret: secret} do
    session =
      Enum.reduce(1..5, sign_in_with_password(), fn _, session ->
        session
        |> fill_in("Authentication code", with: "000000")
        |> click_button("Verify")
      end)

    session
    |> fill_in("Authentication code", with: Fixtures.next_totp_code(secret))
    |> click_button("Verify")
    |> assert_has("[role='alert']", text: "Too many codes tried")
    |> refute_has("#two_factor_use_recovery")
    |> then(&assert(&1.conn.status == 429))
  end

  test "when the app's secret can't be decrypted, says so and takes a recovery code", context do
    %{user: user, secret: secret, recovery_codes: [code | _]} = context

    # As it is once `SECRETS_ENCRYPTION_KEY` has changed.
    Repo.query!("UPDATE user_totps SET secret = $1 WHERE user_id = $2", [<<1, 0::size(40)-unit(8)>>, user.id])

    sign_in_with_password()
    |> fill_in("Authentication code", with: Fixtures.next_totp_code(secret))
    |> click_button("Verify")
    |> assert_path(~p"/login/two-factor")
    |> assert_has("[role='alert']", text: "Your authenticator app can't be checked right now")
    |> assert_has("#two_factor_recovery:not([hidden]) #recovery_code:not([disabled])")
    |> fill_in("Recovery code", with: code)
    |> click_button("Verify")
    |> assert_has("div", text: "You signed in with a recovery code. You have 9 left.")
  end

  test "the code page without a password first goes back to sign in" do
    build_conn()
    |> visit(~p"/login/two-factor")
    |> assert_path(~p"/login")
    |> assert_has("div", text: "Your sign-in timed out")
  end

  test "a sign-in waiting too long has to start again", %{secret: secret, user: user} do
    stale = %{"user_id" => user.id, "started_at" => System.os_time(:second) - 301}

    build_conn()
    |> init_test_session(%{"two_factor_pending" => stale})
    |> post(~p"/login/two-factor", %{"code" => Fixtures.next_totp_code(secret)})
    |> redirected_to()
    |> then(&assert(&1 == ~p"/login"))
  end

  test "signing in as someone else forgets the waiting sign-in" do
    sign_in_with_password()
    |> click_button("Sign in as someone else")
    |> assert_path(~p"/login")
    |> visit(~p"/login/two-factor")
    |> assert_path(~p"/login")
  end

  test "keeps remember me through the code step", %{secret: secret} do
    conn =
      build_conn()
      |> post(~p"/login", %{
        "user" => %{"email" => "sgtpepper@geocities.com", "password" => @password, "remember_me" => "true"}
      })

    assert redirected_to(conn) == ~p"/login/two-factor"
    refute conn.resp_cookies["_nerves_hub_user_remember_me"]

    conn =
      conn
      |> recycle()
      |> post(~p"/login/two-factor", %{"code" => Fixtures.next_totp_code(secret)})

    assert redirected_to(conn) == ~p"/orgs"
    assert conn.resp_cookies["_nerves_hub_user_remember_me"]
  end

  test "a password reset still asks for the code", %{user: user} do
    {token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
    Repo.insert!(user_token)

    conn =
      put(build_conn(), ~p"/password-reset/#{token}", %{
        "user" => %{"password" => "a new password 123", "password_confirmation" => "a new password 123"}
      })

    assert redirected_to(conn) == ~p"/login/two-factor"
  end

  describe "Google sign-in" do
    setup do
      Application.put_env(:nerves_hub, :enable_google_auth, true)
      on_exit(fn -> Application.put_env(:nerves_hub, :enable_google_auth, false) end)

      Mimic.stub(Ueberauth, :call, fn conn, _routes ->
        assigns = Map.put(conn.assigns, :ueberauth_auth, Fixtures.ueberauth_google_success_fixture())
        %{conn | assigns: assigns}
      end)

      :ok
    end

    test "asks for the code too" do
      callback = ~p"/auth/google/callback?state=dummy&code=dummy"
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])
      on_exit(fn -> Application.delete_env(:nerves_hub, :sign_up_methods) end)

      # The first sign-in makes the account.
      build_conn() |> visit(callback) |> assert_path(~p"/orgs")

      {:ok, %User{} = google_user} = Accounts.get_user_by_email(Fixtures.ueberauth_google_success_fixture().info.email)
      Fixtures.two_factor_fixture(google_user)

      build_conn()
      |> visit(callback)
      |> assert_path(~p"/login/two-factor")
    end
  end

  describe "the API's password sign-in" do
    test "is refused once two-factor is on" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/users/auth", %{"email" => "sgtpepper@geocities.com", "password" => @password})

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 401)
      assert detail =~ "two-factor authentication on"
    end
  end
end
