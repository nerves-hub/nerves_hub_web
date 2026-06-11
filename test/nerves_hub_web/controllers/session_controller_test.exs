defmodule NervesHubWeb.SessionControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

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

    test "requires a TOTP code after password authentication when MFA is enabled" do
      user =
        %{
          name: "Sgt Pepper",
          email: "sgtpepper@geocities.com",
          password: "JohnRingoPaulGeorge"
        }
        |> Fixtures.user_fixture()
        |> Fixtures.org_fixture(%{name: "LonelyHeartsClubBand"})
        |> then(fn _org -> Accounts.get_user_by_email("sgtpepper@geocities.com") |> elem(1) end)

      {:ok, setup} = Accounts.start_mfa_setup(user, "JohnRingoPaulGeorge")

      {:ok, _user, _recovery_codes} =
        Accounts.confirm_mfa_setup(user, setup.secret, NimbleTOTP.verification_code(setup.secret))

      user = Accounts.get_user_by_email("sgtpepper@geocities.com") |> elem(1)
      {:ok, _user} = user |> Ecto.Changeset.change(%{mfa_last_used_at: nil}) |> NervesHub.Repo.update()

      build_conn()
      |> visit(~p"/login")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/login/mfa")
      |> assert_has("h1", with: "Enter authentication code")
      |> assert_has("#mfa-code-inputs input[aria-label=\"Authentication code digit 1\"]")
      |> assert_has("#mfa-code-inputs input[aria-label=\"Authentication code digit 6\"]")
      |> assert_has("input[name=\"mfa[code]\"][data-mfa-code-hidden]")
      |> fill_in("Authentication code", with: NimbleTOTP.verification_code(setup.secret))
      |> submit()
      |> assert_path(~p"/orgs")
    end

    test "accepts a recovery code from the recovery-code field" do
      user =
        %{
          name: "Sgt Pepper",
          email: "sgtpepper@geocities.com",
          password: "JohnRingoPaulGeorge"
        }
        |> Fixtures.user_fixture()
        |> Fixtures.org_fixture(%{name: "LonelyHeartsClubBand"})
        |> then(fn _org -> Accounts.get_user_by_email("sgtpepper@geocities.com") |> elem(1) end)

      {:ok, setup} = Accounts.start_mfa_setup(user, "JohnRingoPaulGeorge")

      {:ok, _user, [recovery_code | _]} =
        Accounts.confirm_mfa_setup(user, setup.secret, NimbleTOTP.verification_code(setup.secret))

      build_conn()
      |> visit(~p"/login")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/login/mfa")
      |> fill_in("Recovery code", with: recovery_code)
      |> submit()
      |> assert_path(~p"/orgs")
    end

    test "clears pending MFA login after too many invalid codes" do
      user =
        %{
          name: "Sgt Pepper",
          email: "sgtpepper@geocities.com",
          password: "JohnRingoPaulGeorge"
        }
        |> Fixtures.user_fixture()
        |> Fixtures.org_fixture(%{name: "LonelyHeartsClubBand"})
        |> then(fn _org -> Accounts.get_user_by_email("sgtpepper@geocities.com") |> elem(1) end)

      {:ok, setup} = Accounts.start_mfa_setup(user, "JohnRingoPaulGeorge")

      {:ok, _user, _recovery_codes} =
        Accounts.confirm_mfa_setup(user, setup.secret, NimbleTOTP.verification_code(setup.secret))

      session =
        build_conn()
        |> visit(~p"/login")
        |> fill_in("Email address", with: "sgtpepper@geocities.com")
        |> fill_in("Password", with: "JohnRingoPaulGeorge")
        |> submit()
        |> assert_path(~p"/login/mfa")

      session =
        Enum.reduce(1..8, session, fn _, session ->
          session
          |> fill_in("Recovery code", with: "WRNG-CODE")
          |> submit()
        end)

      session
      |> assert_path(~p"/login")
      |> assert_has("div", text: "Too many invalid authentication codes. Please sign in again.")
    end
  end
end
