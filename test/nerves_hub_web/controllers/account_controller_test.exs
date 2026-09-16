defmodule NervesHubWeb.AccountControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "new" do
    test "renders registration form when registrations are enabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create a new account")
    end

    test "redirects to /login with a flash when registrations are disabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, false)

      build_conn()
      |> visit(~p"/register")
      |> assert_path(~p"/login")
      |> assert_has("[role='alert']", text: "Please contact support for an invite to this platform.")
    end
  end

  describe "create" do
    test "registers new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create a new account")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Email address", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_has("h1", text: "Please confirm your email")
      |> assert_has("p", text: "Your new account was created successfully!")

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      send_queued_emails()

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Confirm your account"
        assert to_string(email.text_body) =~ "Thanks for creating an account with NervesHub."
        assert email.html_body =~ "Thanks for creating an account with NervesHub."
      end)
    end

    test "requires name, email, and password, to create a new account" do
      Application.put_env(:nerves_hub, :open_for_registrations, true)

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create a new account")
      |> fill_in("Name", with: "")
      |> fill_in("Email address", with: "")
      |> fill_in("Password", with: "")
      |> submit()
      |> assert_path(~p"/register")
      |> assert_has("p", text: "can't be blank", count: 3)

      send_queued_emails()

      refute_email_sent()
    end

    test "doesn't register an account when registrations are disabled" do
      Application.put_env(:nerves_hub, :open_for_registrations, false)

      conn =
        post(build_conn(), ~p"/register", %{
          "user" => %{
            "name" => "Sgt Pepper",
            "email" => "sgtpepper@geocities.com",
            "password" => "JohnRingoPaulGeorge"
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Accounts.get_user_by_email("sgtpepper@geocities.com") == {:error, :not_found}

      send_queued_emails()

      refute_email_sent()
    end

    test "confirm account and be logged in" do
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

      send_queued_emails()

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Welcome Sgt Pepper!"
        assert to_string(email.text_body) =~ "Welcome to #{platform_name}!"
        assert email.html_body =~ "Welcome to #{platform_name}!"
      end)
    end

    test "send new confirm account email if the token is older than 1 day" do
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
        text: "It looks like your confirmation link has expired. A new link has been sent to your email."
      )

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      send_queued_emails()

      assert_email_sent(fn email ->
        assert email.subject == "#{platform_name}: Confirm your account"
        assert to_string(email.text_body) =~ "Please use the link below to confirm your account:"
        assert email.html_body =~ "Please click the button below to confirm your account:"
      end)
    end
  end

  describe "invite" do
    test "- registering from an invite joins the org and logs the user in", %{org: org, user: user} do
      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_has("h1", text: "You've been invited to join #{org.name} on #{platform_name}")
      |> refute_has("body", text: "joe@example.com")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs")
      |> assert_has("[role='alert']", text: "Welcome to NervesHub!")
      |> assert_has("div", text: org.name)

      send_queued_emails()

      # don't send email to admin who added the user
      refute_email_sent(subject: "NervesHub: Sgt Pepper has been added to Jeff")
    end

    test "- an invitee with an account is asked to sign in first", %{org: org, user: user} do
      invitee = Fixtures.user_fixture(%{name: "Ringo"})

      {:ok, invite} = Accounts.invite(%{"email" => invitee.email, "role" => "view"}, org, user)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_has("p", text: "Sign in with the invited email address to accept this invitation.")
      |> refute_has("button", text: "Register")
      # the link is a bearer token, so don't tell whoever holds it who was invited
      |> refute_has("body", text: invitee.email)

      assert Accounts.get_org_user(org, invitee) == {:error, :not_found}
    end

    test "- a signed in invitee accepts the invite", %{org: org, user: user} do
      invitee = Fixtures.user_fixture(%{name: "Ringo"})

      {:ok, invite} = Accounts.invite(%{"email" => invitee.email, "role" => "manage"}, org, user)

      invitee
      |> signed_in_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> click_button("Join #{org.name}")
      |> assert_path(~p"/org/#{org.name}")

      assert {:ok, %{role: :manage}} = Accounts.get_org_user(org, invitee)
      assert Repo.reload(invite).accepted
    end

    test "- a signed in invitee declines the invite", %{org: org, user: user} do
      invitee = Fixtures.user_fixture(%{name: "Ringo"})

      {:ok, invite} = Accounts.invite(%{"email" => invitee.email, "role" => "view"}, org, user)

      invitee
      |> signed_in_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> click_button("Decline")
      |> assert_path(~p"/orgs")

      assert Accounts.get_org_user(org, invitee) == {:error, :not_found}
      assert Repo.reload(invite).declined_at
      assert Accounts.get_invites_for_org(org) == []
    end

    test "- someone signed in as another user is told who the invite is for", %{
      org: org,
      user: user
    } do
      someone_else = Fixtures.user_fixture(%{name: "Ringo"})

      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      someone_else
      |> signed_in_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_has("p",
        text: "This invitation was sent to a different email address. You're signed in as #{someone_else.email}."
      )
      |> refute_has("body", text: "joe@example.com")

      assert Accounts.get_org_user(org, someone_else) == {:error, :not_found}
    end

    test "- an accepted invite can't be used again", %{org: org, user: user} do
      invitee = Fixtures.user_fixture(%{name: "Ringo"})

      {:ok, invite} = Accounts.invite(%{"email" => invitee.email, "role" => "view"}, org, user)
      {:ok, _org_user} = Accounts.accept_invite(invite, invitee)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_path(~p"/login")
      |> assert_has("div", text: "Invalid or expired invite")
    end
  end

  defp signed_in_conn(user) do
    token = Accounts.create_user_session_token(user)

    build_conn()
    |> init_test_session(%{"user_token" => token})
  end
end
