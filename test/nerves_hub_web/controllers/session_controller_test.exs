defmodule NervesHubWeb.SessionControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "confirm account" do
    test "and log in user" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      params = %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }

      {:ok, user} = Accounts.create_user(params)

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "confirm", nil)
      Repo.insert!(user_token)

      build_conn()
      |> visit(~p"/confirm/#{encoded_token}")
      |> assert_path(~p"/orgs")

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Welcome Sgt Pepper!"
        assert to_string(email.text_body) =~ "Welcome to #{platform_name}!"
        assert email.html_body =~ "Welcome to #{platform_name}!"
      end)
    end

    test "and send new confirm account email if the token is older than 1 day" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      params = %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }

      {:ok, user} = Accounts.create_user(params)

      {encoded_token, user_token} = UserToken.build_hashed_token(user, "confirm", nil)

      twenty_five_hours_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-25, :hour)
        |> NaiveDateTime.truncate(:second)

      user_token
      |> Map.put(:inserted_at, twenty_five_hours_ago)
      |> Repo.insert!()

      build_conn()
      |> visit(~p"/confirm/#{encoded_token}")
      |> assert_path(~p"/confirm/#{encoded_token}")
      |> assert_has("p",
        with: "It looks like your confirmation link has expired. A new link has been sent to your email."
      )

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Confirm your account"
        assert to_string(email.text_body) =~ "Please use the link below to confirm your account:"
        assert email.html_body =~ "Please click the button below to confirm your account:"
      end)
    end
  end

  describe "create session" do
    test "redirected to the orgs page when logging in" do
      %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }
      |> Fixtures.user_fixture()
      |> Fixtures.org_fixture(%{name: "LonelyHeartsClubBand"})

      build_conn()
      |> visit(~p"/login")
      |> assert_has("h1", with: "Sign in to your account")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs")
    end

    test "redirected to original URL when logging in" do
      %{
        name: "Sgt Pepper",
        email: "sgtpepper@geocities.com",
        password: "JohnRingoPaulGeorge"
      }
      |> Fixtures.user_fixture()
      |> Fixtures.org_fixture(%{name: "LonelyHeartsClubBand"})

      build_conn()
      |> visit(~p"/orgs/new")
      |> assert_has("h1", with: "Sign in to your account")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs/new")
    end
  end

  describe "external login redirects" do
    setup do
      previous = Application.get_env(:nerves_hub, :external_login_return_urls)

      Application.put_env(:nerves_hub, :external_login_return_urls, [
        "https://admin.example.com"
      ])

      on_exit(fn ->
        if previous do
          Application.put_env(:nerves_hub, :external_login_return_urls, previous)
        else
          Application.delete_env(:nerves_hub, :external_login_return_urls)
        end
      end)

      user =
        %{
          name: "Sgt Pepper",
          email: "sgtpepper@geocities.com",
          password: "JohnRingoPaulGeorge"
        }
        |> Fixtures.user_fixture()

      Fixtures.org_fixture(user, %{name: "LonelyHeartsClubBand"})

      %{user: user}
    end

    test "GET /login stores an allow-listed external return_to in the session" do
      return_to = "https://admin.example.com/oauth/authorize?client_id=abc"

      conn = get(build_conn(), ~p"/login?#{[return_to: return_to]}")

      assert get_session(conn, :login_redirect_path) == return_to
    end

    test "GET /login ignores a non-allow-listed external return_to" do
      conn = get(build_conn(), ~p"/login?#{[return_to: "https://evil.example.com/steal"]}")

      refute get_session(conn, :login_redirect_path)
    end

    test "GET /login ignores a protocol-relative return_to" do
      conn = get(build_conn(), ~p"/login?#{[return_to: "//evil.example.com"]}")

      refute get_session(conn, :login_redirect_path)
    end

    test "logging in redirects to the stored allow-listed external URL" do
      return_to = "https://admin.example.com/oauth/authorize?client_id=abc"

      conn =
        build_conn()
        |> init_test_session(%{"login_redirect_path" => return_to})
        |> post(~p"/login", %{
          "user" => %{"email" => "sgtpepper@geocities.com", "password" => "JohnRingoPaulGeorge"}
        })

      assert redirected_to(conn) == return_to
    end

    test "logging in falls back to the default path for a non-allow-listed URL" do
      conn =
        build_conn()
        |> init_test_session(%{"login_redirect_path" => "https://evil.example.com/steal"})
        |> post(~p"/login", %{
          "user" => %{"email" => "sgtpepper@geocities.com", "password" => "JohnRingoPaulGeorge"}
        })

      assert redirected_to(conn) == ~p"/orgs"
    end

    test "the external return_to survives the full login round-trip" do
      return_to = "https://admin.example.com/oauth/authorize?client_id=abc"

      conn =
        build_conn()
        |> get(~p"/login?#{[return_to: return_to]}")
        |> recycle()
        |> post(~p"/login", %{
          "user" => %{"email" => "sgtpepper@geocities.com", "password" => "JohnRingoPaulGeorge"}
        })

      assert redirected_to(conn) == return_to
    end
  end
end
