defmodule NervesHubWeb.OAuthControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Mimic

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "google auth enabled" do
    setup do
      Application.put_env(:nerves_hub, :enable_google_auth, true)

      on_exit(fn ->
        Application.put_env(:nerves_hub, :enable_google_auth, false)
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
end
