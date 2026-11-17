defmodule NervesHub.Accounts.SignInMethodsTest do
  # Not async: Google sign-in is turned on and off through app config.
  use NervesHub.DataCase, async: false

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    Application.put_env(:nerves_hub, :enable_google_auth, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :enable_google_auth, false) end)
  end

  # An account linked to Google, with its password (the fixture's) unless
  # `password: false`.
  defp google_user(opts \\ []) do
    user = Fixtures.user_fixture()
    changes = [google_id: "google-#{user.id}"]
    changes = if Keyword.get(opts, :password, true), do: changes, else: [{:password_hash, nil} | changes]

    user |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  describe "sign_in_methods/1" do
    test "lists the ways the account signs in" do
      assert Accounts.sign_in_methods(Fixtures.user_fixture()) == [:password]
      assert Accounts.sign_in_methods(google_user()) == [:password, :google]
      assert Accounts.sign_in_methods(google_user(password: false)) == [:google]
    end

    test "leaves Google out when this server doesn't offer it" do
      Application.put_env(:nerves_hub, :enable_google_auth, false)

      assert Accounts.sign_in_methods(google_user()) == [:password]
      assert Accounts.sign_in_methods(google_user(password: false)) == []
    end
  end

  describe "remove_password/2" do
    test "removes it from an account that signs in with Google, and signs its other sessions out" do
      user = google_user()
      this_session = Accounts.create_user_session_token(user)
      other_session = Accounts.create_user_session_token(user)

      assert {:ok, %User{password_hash: nil}} = Accounts.remove_password(user, this_session)

      assert Accounts.get_user_by_session_token(this_session)
      refute Accounts.get_user_by_session_token(other_session)
      assert Accounts.get_user_by_email_and_password(user.email, "test_password") == nil
    end

    test "won't remove the only way in" do
      user = Fixtures.user_fixture()

      assert Accounts.remove_password(user, nil) == {:error, :last_sign_in_method}
      assert Repo.reload(user).password_hash
    end

    test "won't remove it while this server doesn't offer Google sign-in" do
      Application.put_env(:nerves_hub, :enable_google_auth, false)
      user = google_user()

      assert Accounts.remove_password(user, nil) == {:error, :last_sign_in_method}
    end

    test "says when there's no password to remove" do
      assert Accounts.remove_password(google_user(password: false), nil) == {:error, :no_password}
    end
  end

  describe "disconnect_google/2" do
    test "unlinks Google from an account with a password, and signs its other sessions out" do
      user = google_user()
      this_session = Accounts.create_user_session_token(user)
      other_session = Accounts.create_user_session_token(user)

      assert {:ok, %User{google_id: nil, google_hd: nil}} = Accounts.disconnect_google(user, this_session)

      assert Accounts.get_user_by_session_token(this_session)
      refute Accounts.get_user_by_session_token(other_session)
    end

    test "won't unlink the only way in" do
      user = google_user(password: false)

      assert Accounts.disconnect_google(user, nil) == {:error, :last_sign_in_method}
      assert Repo.reload(user).google_id
    end

    # Two tabs each loaded the account with both ways in, and each removes one.
    test "keeps one way in when the caller's copy of the account is out of date" do
      user = google_user()

      assert {:ok, _user} = Accounts.remove_password(user, nil)
      assert Accounts.disconnect_google(user, nil) == {:error, :last_sign_in_method}

      assert Repo.reload(user).google_id
    end

    test "says when there's no Google account to unlink" do
      assert Accounts.disconnect_google(Fixtures.user_fixture(), nil) == {:error, :not_connected}
    end
  end

  describe "set_user_password/3" do
    test "gives a Google account a password, and emails to say so" do
      user = google_user(password: false)
      password = "a long enough password"

      assert {:ok, user} =
               Accounts.set_user_password(
                 user,
                 %{"password" => password, "password_confirmation" => password},
                 &"/reset/#{&1}"
               )

      assert User.valid_password?(user, password)

      send_queued_emails()
      assert_email_sent(subject: "NervesHub: Your password has been updated")
    end

    test "checks the password like a new one" do
      user = google_user(password: false)

      assert {:error, changeset} =
               Accounts.set_user_password(
                 user,
                 %{"password" => "short", "password_confirmation" => "nope"},
                 &"/reset/#{&1}"
               )

      assert %{password: [_ | _], password_confirmation: [_ | _]} = errors_on(changeset)
    end

    test "won't replace a password that's set, which needs the old one" do
      assert Accounts.set_user_password(google_user(), %{"password" => "a long enough password"}, &"/reset/#{&1}") ==
               {:error, :already_set}
    end
  end

  describe "connect_google_account/2" do
    test "links the Google account for the account's email" do
      auth = Fixtures.ueberauth_google_success_fixture()
      user = Fixtures.user_fixture(%{email: auth.info.email})

      assert {:ok, %User{google_id: google_id}} = Accounts.connect_google_account(user, auth)
      assert google_id == auth.uid
    end

    test "won't link a Google account for another address" do
      auth = Fixtures.ueberauth_google_success_fixture()

      assert Accounts.connect_google_account(Fixtures.user_fixture(), auth) == {:error, :email_mismatch}
    end

    test "won't link an address Google hasn't verified" do
      auth = Fixtures.ueberauth_google_success_fixture()
      auth = put_in(auth.extra.raw_info.user["email_verified"], false)
      user = Fixtures.user_fixture(%{email: auth.info.email})

      assert Accounts.connect_google_account(user, auth) == {:error, :email_not_verified}
    end
  end

  describe "update_user/3 for an account without a password" do
    test "saves its name" do
      user = google_user(password: false)

      assert {:ok, %User{name: "New Name"}, nil} =
               Accounts.update_user(user, %{"name" => "New Name", "current_password" => ""}, &"/c/#{&1}")
    end
  end

  describe "update_user/3 for an account linked to Google" do
    test "won't change its email, which follows Google's" do
      user = google_user()

      assert {:error, changeset} =
               Accounts.update_user(
                 user,
                 %{"email" => "new@example.com", "current_password" => "test_password"},
                 &"/c/#{&1}"
               )

      assert %{email: ["follows your Google account, so it changes there"]} = errors_on(changeset)
    end

    test "changes its email like any other's while this server doesn't offer Google sign-in" do
      Application.put_env(:nerves_hub, :enable_google_auth, false)
      user = google_user()

      assert {:ok, _user, "new@example.com"} =
               Accounts.update_user(
                 user,
                 %{"email" => "new@example.com", "current_password" => "test_password"},
                 &"/c/#{&1}"
               )
    end
  end

  test "a password typed for an email change on an account without one is just wrong" do
    user = Fixtures.user_fixture() |> Ecto.Changeset.change(password_hash: nil) |> Repo.update!()

    assert {:error, changeset} =
             Accounts.update_user(user, %{"email" => "new@example.com", "current_password" => "anything"}, &"/c/#{&1}")

    assert %{current_password: ["Current password is incorrect."]} = errors_on(changeset)
  end
end
