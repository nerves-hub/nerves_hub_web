defmodule NervesHubWeb.OAuthControllerTest do
  # Not async: the tests flip app config other tests read (Google sign-in and
  # the sign up methods).
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "google auth enabled" do
    setup do
      Application.put_env(:nerves_hub, :enable_google_auth, true)
      sign_up_methods = Application.fetch_env(:nerves_hub, :sign_up_methods)

      on_exit(fn ->
        Application.put_env(:nerves_hub, :enable_google_auth, false)

        case sign_up_methods do
          {:ok, value} -> Application.put_env(:nerves_hub, :sign_up_methods, value)
          :error -> Application.delete_env(:nerves_hub, :sign_up_methods)
        end
      end)
    end

    test "shows google auth button if enabled" do
      build_conn()
      |> visit(~p"/login")
      |> assert_has("h1", text: "Sign in to #{platform_name()}")
      |> assert_has("a[href='/auth/google']", text: "Continue with Google")
      |> assert_has("div", text: "or sign in with email")
    end

    test "create new account successfully" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

      Mimic.stub(Ueberauth, :call, fn conn, _routes ->
        google_auth = Fixtures.ueberauth_google_success_fixture()
        assigns = Map.put(conn.assigns, :ueberauth_auth, google_auth)
        %{conn | assigns: assigns}
      end)

      build_conn()
      |> visit(~p"/auth/google/callback?state=dummy&code=dummy&scope=email+profile&prompt=none")
      |> assert_path("/orgs")
      |> assert_has("div", text: "Welcome back!")

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: Welcome Jane Person!")
    end

    test "doesn't create an account when registrations are closed" do
      Application.put_env(:nerves_hub, :sign_up_methods, [])

      build_conn()
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path("/login")
      |> assert_has("div", text: "There's no account for jane@person.com.")

      assert Accounts.get_user_by_email("jane@person.com") == {:error, :not_found}
    end

    test "creates the account of someone invited to an org while registrations are closed, who can then join it",
         %{org: org, user: admin} do
      Application.put_env(:nerves_hub, :sign_up_methods, [])

      {:ok, invite} = Accounts.invite(%{"email" => "jane@person.com", "role" => "view"}, org, admin)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path(~p"/invite/#{invite.token}")
      |> click_button("Join #{org.name}")

      {:ok, user} = Accounts.get_user_by_email("jane@person.com")
      assert Accounts.has_org_role?(org, user, :view)
    end

    test "signs in the account linked to the Google account, even with registrations closed" do
      Application.put_env(:nerves_hub, :sign_up_methods, [])

      google_auth = Fixtures.ueberauth_google_success_fixture()
      {:ok, _user} = %User{} |> User.oauth_changeset(google_auth) |> Repo.insert()

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/orgs")
      |> assert_has("div", text: "Welcome back!")
    end

    test "refuses an email address Google hasn't verified" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

      google_auth = put_in(Fixtures.ueberauth_google_success_fixture().extra.raw_info.user["email_verified"], false)

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/login")
      |> assert_has("div", text: "Google hasn't verified jane@person.com, so it can't be used to sign in.")

      assert Accounts.get_user_by_email("jane@person.com") == {:error, :not_found}
    end

    test "creates an account when sign up is open to Google only, which the sign up form isn't" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:google])

      build_conn()
      |> visit(~p"/register")
      |> assert_path(~p"/login")
      |> assert_has("[role='alert']", text: "Sign in with Google to create an account.")
      |> assert_has("p", text: "Don't have an account? Sign in with Google to create one.")
      |> refute_has("a[href='/register']")
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path("/orgs")

      assert {:ok, _user} = Accounts.get_user_by_email("jane@person.com")
    end

    test "doesn't create an account when sign up is open to the sign up form only" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password])

      build_conn()
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path("/login")
      |> assert_has("div", text: "There's no account for jane@person.com.")

      assert Accounts.get_user_by_email("jane@person.com") == {:error, :not_found}
    end

    # Someone registers the address and never confirms it, hoping its owner
    # signs in with Google and ends up sharing the account with them.
    test "doesn't sign in to or confirm an unconfirmed account that has the address" do
      {:ok, squatter} =
        Accounts.create_user(%{name: "Mallory", email: "jane@person.com", password: "mallorys_password"})

      build_conn()
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path("/login")
      |> assert_has("div", text: "An account with jane@person.com already exists.")
      |> visit(~p"/orgs")
      |> assert_path("/login")

      squatter = Repo.reload(squatter)
      assert is_nil(squatter.google_id)
      assert is_nil(squatter.confirmed_at)
    end

    # Someone puts the address on their own confirmed account, which the
    # account page allowed without confirming it.
    test "doesn't sign in to someone else's account that has the address" do
      squatter = Fixtures.user_fixture(%{name: "Mallory"})
      squatter = squatter |> Ecto.Changeset.change(email: "jane@person.com") |> Repo.update!()

      build_conn()
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> assert_path("/login")
      |> assert_has("div", text: "An account with jane@person.com already exists.")
      |> visit(~p"/orgs")
      |> assert_path("/login")

      assert is_nil(Repo.reload(squatter).google_id)
    end

    test "links an account to Google once its password is given" do
      user = Fixtures.user_fixture(%{email: "jane@person.com"})
      google_auth = Fixtures.ueberauth_google_success_fixture()

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/login")
      |> fill_in("Email", with: "jane@person.com")
      |> fill_in("Password", with: "test_password")
      |> click_button("Sign in")
      |> assert_path("/orgs")
      |> assert_has("div", text: "Your Google account is now connected.")

      assert Repo.reload(user).google_id == google_auth.uid

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/orgs")
      |> assert_has("div", text: "Welcome back!")
    end

    # Its owner can't sign in with a password they don't know, so they reset
    # it, which proves the address is theirs.
    test "links an unconfirmed account to Google once its password is reset, and confirms it" do
      {:ok, squatter} =
        Accounts.create_user(%{name: "Mallory", email: "jane@person.com", password: "mallorys_password"})

      google_auth = Fixtures.ueberauth_google_success_fixture()
      {encoded_token, user_token} = UserToken.build_hashed_token(squatter, "reset_password", nil)
      Repo.insert!(user_token)

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/login")
      |> assert_has("div", text: "or reset the password if you don't know it")
      |> visit(~p"/password-reset/#{encoded_token}")
      |> fill_in("New password", with: "janes_new_password")
      |> fill_in("Confirm new password", with: "janes_new_password")
      |> submit()
      |> assert_path("/orgs")
      |> assert_has("div", text: "Your Google account is now connected.")

      user = Repo.reload(squatter)
      assert user.google_id == google_auth.uid
      refute is_nil(user.confirmed_at)
      assert Accounts.authenticate("jane@person.com", "mallorys_password") == {:error, :authentication_failed}
    end

    test "doesn't link Google to a different account signed in to afterwards" do
      user = Fixtures.user_fixture(%{email: "jane@person.com"})
      someone_else = Fixtures.user_fixture()

      build_conn()
      |> google_callback(Fixtures.ueberauth_google_success_fixture())
      |> fill_in("Email", with: someone_else.email)
      |> fill_in("Password", with: "test_password")
      |> click_button("Sign in")
      |> assert_path("/orgs")
      |> refute_has("div", text: "Your Google account is now connected.")

      assert is_nil(Repo.reload(someone_else).google_id)
      assert is_nil(Repo.reload(user).google_id)
    end

    test "refuses an account without a password that's linked to a different Google account" do
      google_auth = Fixtures.ueberauth_google_success_fixture()

      {:ok, _user} =
        %User{} |> User.oauth_changeset(%{google_auth | uid: "a-different-google-account"}) |> Repo.insert()

      build_conn()
      |> google_callback(google_auth)
      |> assert_path("/login")
      |> assert_has("div", text: "The account with jane@person.com is connected to a different Google account.")
    end

    test "shows the failure page if an error occurs" do
      Mimic.stub(Ueberauth, :call, fn conn, _routes ->
        assigns = Map.put(conn.assigns, :ueberauth_failure, true)
        %{conn | assigns: assigns}
      end)

      build_conn()
      |> visit(~p"/auth/google/callback?state=dummy&code=dummy&scope=email+profile&prompt=none")
      |> assert_has("h1", text: "We couldn't sign you in with Google")
    end

    test "shows the failure page if the Google name can't be used for a new account" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:google])

      Mimic.stub(Ueberauth, :call, fn conn, _routes ->
        google_auth = Fixtures.ueberauth_google_success_fixture()
        google_auth = put_in(google_auth.info.name, "Jane Person (she/her)")
        assigns = Map.put(conn.assigns, :ueberauth_auth, google_auth)
        %{conn | assigns: assigns}
      end)

      build_conn()
      |> visit(~p"/auth/google/callback?state=dummy&code=dummy&scope=email+profile&prompt=none")
      |> assert_has("h1", text: "We couldn't sign you in with Google")

      refute Repo.get_by(User, email: "jane@person.com")

      send_queued_emails()

      refute_email_sent()
    end

    test "doesn't send a reset password email if the user logged in with Google" do
      google_auth = Fixtures.ueberauth_google_success_fixture()

      {:ok, user} =
        %User{}
        |> User.oauth_changeset(google_auth)
        |> Repo.insert()

      build_conn()
      |> visit(~p"/password-reset")
      |> assert_has("h1", text: "Forgot your password?")
      |> fill_in("Email", with: user.email)
      |> submit()
      |> assert_path(~p"/password-reset")
      |> assert_has("h1", text: "Check your email")

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: Login with Google")
    end
  end

  describe "unknown provider" do
    test "is not found" do
      assert build_conn() |> get(~p"/auth/login") |> html_response(404)
      assert build_conn() |> get("/auth/.env") |> html_response(404)
    end

    test "has no callback" do
      assert build_conn() |> get(~p"/auth/login/callback") |> html_response(404)
    end
  end

  describe "google auth disabled" do
    setup do
      Application.put_env(:nerves_hub, :enable_google_auth, false)
    end

    test "does not show google auth button if not enabled" do
      build_conn()
      |> visit(~p"/login")
      |> assert_has("h1", text: "Sign in to #{platform_name()}")
      |> refute_has("a[href='/auth/google']")
      |> refute_has("div", text: "or sign in with email")
    end
  end

  defp platform_name(), do: Application.get_env(:nerves_hub, :support_email_platform_name)

  defp google_callback(conn_or_session, google_auth) do
    Mimic.stub(Ueberauth, :call, fn conn, _routes ->
      %{conn | assigns: Map.put(conn.assigns, :ueberauth_auth, google_auth)}
    end)

    visit(conn_or_session, ~p"/auth/google/callback?state=dummy&code=dummy&scope=email+profile&prompt=none")
  end
end
