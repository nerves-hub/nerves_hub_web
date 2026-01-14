defmodule NervesHubWeb.OAuthControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

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
      |> assert_has("h1", with: "Sign in to your account")
      |> assert_has("span", with: "Or create a new account with")
      |> assert_has("span", with: "Google")
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
      |> assert_has("div", with: "Welcome back!")

      assert_email_sent(subject: "NervesHub: Welcome Jane Person!")
    end

    test "shows the failure page if an error occurs" do
      Mimic.stub(Ueberauth, :call, fn conn, _routes ->
        assigns = Map.put(conn.assigns, :ueberauth_failure, true)
        %{conn | assigns: assigns}
      end)

      build_conn()
      |> visit(~p"/auth/google/callback?state=dummy&code=dummy&scope=email+profile&prompt=none")
      |> assert_has("h1", with: "We were unable to sign you in.")
    end

    test "doesn't send a reset password email if the user logged in with Google" do
      google_auth = Fixtures.ueberauth_google_success_fixture()

      {:ok, user} =
        %User{}
        |> User.oauth_changeset(google_auth)
        |> Repo.insert()

      build_conn()
      |> visit(~p"/password-reset")
      |> assert_has("h1", with: "Reset your password")
      |> fill_in("Email", with: user.email)
      |> submit()
      |> assert_path(~p"/password-reset")
      |> assert_has("h1", with: "Time to check your email")

      assert_email_sent(subject: "NervesHub: Login with Google")
    end
  end

  describe "google auth disabled" do
    setup do
      Application.put_env(:nerves_hub, :enable_google_auth, false)
    end

    test "does not show google auth button if not enabled" do
      build_conn()
      |> visit(~p"/login")
      |> assert_has("h1", with: "Sign in to your account")
      |> refute_has("span", text: "Or create a new account with")
      |> refute_has("span", text: "Google")
    end
  end
end
