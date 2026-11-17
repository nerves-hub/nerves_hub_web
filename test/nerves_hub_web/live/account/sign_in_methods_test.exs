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

  # An account linked to Google, with the fixture's password unless
  # `password: false`.
  defp google_user(opts \\ []) do
    user = Fixtures.user_fixture()
    changes = [google_id: "google-#{user.id}"]
    changes = if Keyword.get(opts, :password, true), do: changes, else: [{:password_hash, nil} | changes]

    user |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  # Signed in as `user`, just now unless `recent: false`.
  defp signed_in(user, opts \\ []) do
    session = %{"user_token" => Accounts.create_user_session_token(user)}

    session =
      if Keyword.get(opts, :recent, true),
        do: Map.put(session, "authenticated_at", System.os_time(:second)),
        else: session

    init_test_session(build_conn(), session)
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
    |> signed_in()
    |> visit("/account")
    |> assert_has("#recent-sign-in", text: "You signed in recently")

    Fixtures.user_fixture()
    |> signed_in(recent: false)
    |> visit("/account")
    |> refute_has("#recent-sign-in")
  end

  test "removes the password of an account that signs in with Google, and signs its other browsers out" do
    user = google_user()
    elsewhere = Accounts.create_user_session_token(user)

    user
    |> signed_in()
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
    user = google_user()

    user
    |> signed_in()
    |> visit("/account")
    |> click_button("#disconnect-google", "Disconnect")
    |> assert_has("div", text: "Your Google account is disconnected")
    |> assert_has("#sign-in-method-google", text: "Not connected")
    |> refute_has("#remove-password")

    refute Repo.reload(user).google_id
  end

  test "gives an account that signs in with Google a password" do
    user = google_user(password: false)
    password = "a long enough password"

    user
    |> signed_in()
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
    user = google_user()

    user
    |> signed_in(recent: false)
    |> visit("/account")
    |> click_button("#remove-password", "Remove")
    |> assert_path("/account/confirm", query_params: %{return_to: "/account"})

    assert Repo.reload(user).password_hash
  end

  test "an account that signs in with Google shows the email Google gives it, which can't be changed here" do
    google_user(password: false)
    |> signed_in()
    |> visit("/account")
    |> assert_has("#email_input[readonly]")
    |> assert_has("#email_follows_google")
    |> refute_has("#details-form input[name='user[current_password]']")
  end
end
