defmodule NervesHubWeb.Live.Account.SignInMethodsTest do
  # Not async: Google sign-in is turned on through app config.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    Application.put_env(:nerves_hub, :enable_google_auth, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :enable_google_auth, false) end)
  end

  test "an account with only a password can connect Google, and can't remove its password", %{conn: conn} do
    conn
    |> visit("/account")
    |> assert_has("#sign-in-method-google", text: "Not connected")
    |> assert_has("#connect-google")
    |> assert_has("#sign-in-method-password", text: "Set")
    |> refute_has("#remove-password")
  end

  test "says how long the sign-in counts as recent" do
    Fixtures.user_fixture()
    |> signed_in_conn()
    |> visit("/account")
    |> assert_has("#recent-sign-in", text: "You signed in recently")

    Fixtures.user_fixture()
    |> signed_in_conn(recent: false)
    |> visit("/account")
    |> refute_has("#recent-sign-in")
  end

  test "removes the password of an account that signs in with Google, and signs its other browsers out" do
    user = Fixtures.google_user_fixture()
    elsewhere = Accounts.create_user_session_token(user)

    user
    |> signed_in_conn()
    |> visit("/account")
    |> click_button("#remove-password", "Remove")
    |> assert_has("div", text: "Your password is removed")
    |> assert_has("#sign-in-method-password", text: "Not set")
    # Google is the only way in now.
    |> refute_has("#disconnect-google")

    refute Repo.reload(user).password_hash
    refute Accounts.get_user_by_session_token(elsewhere)
  end

  test "disconnects Google from an account with a password" do
    user = Fixtures.google_user_fixture()

    user
    |> signed_in_conn()
    |> visit("/account")
    |> click_button("#disconnect-google", "Disconnect")
    |> assert_has("div", text: "Your Google account is disconnected")
    |> assert_has("#sign-in-method-google", text: "Not connected")
    |> refute_has("#remove-password")

    refute Repo.reload(user).google_id
  end

  test "gives an account that signs in with Google a password" do
    user = Fixtures.google_user_fixture(password: false)
    password = "a long enough password"

    user
    |> signed_in_conn()
    |> visit("/account")
    |> refute_has("#disconnect-google")
    |> click_button("#start-set-password", "Set a password")
    |> within("#set-password-form", fn session ->
      session
      |> fill_in("New password", with: password)
      |> fill_in("Confirm new password", with: password)
      |> submit()
    end)
    |> assert_has("div", text: "Your password is set.")
    |> assert_has("#sign-in-method-password", text: "Set")

    assert User.valid_password?(Repo.reload(user), password)
  end

  test "asks a browser that didn't sign in recently to confirm it's them before removing a way in" do
    user = Fixtures.google_user_fixture()

    user
    |> signed_in_conn(recent: false)
    |> visit("/account")
    |> click_button("#remove-password", "Remove")
    |> assert_path("/account/confirm", query_params: %{return_to: "/account"})

    assert Repo.reload(user).password_hash
  end

  test "an account that signs in with Google shows the email Google gives it, which can't be changed here" do
    Fixtures.google_user_fixture(password: false)
    |> signed_in_conn()
    |> visit("/account")
    |> assert_has("#email_input[readonly]")
    |> assert_has("#email_follows_google")
    |> refute_has("#details-form input[name='user[current_password]']")
  end

  test "an account linked to Google changes its email here while this server doesn't offer Google sign-in" do
    Application.put_env(:nerves_hub, :enable_google_auth, false)

    Fixtures.google_user_fixture()
    |> signed_in_conn()
    |> visit("/account")
    |> refute_has("#email_follows_google")
    |> assert_has("#details-form input[name='user[email]']:not([readonly])")
  end
end
