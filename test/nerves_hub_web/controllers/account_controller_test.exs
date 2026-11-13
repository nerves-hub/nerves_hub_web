defmodule NervesHubWeb.AccountControllerTest do
  # Not async: the tests flip the app-wide sign up setting other tests read.
  use NervesHubWeb.ConnCase.Browser, async: false

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.InviteLinks

  describe "new" do
    test "renders registration form when registrations are enabled" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create your account")
    end

    test "redirects to /login with a flash when registrations are disabled" do
      Application.put_env(:nerves_hub, :sign_up_methods, [])

      build_conn()
      |> visit(~p"/register")
      |> assert_path(~p"/login")
      |> assert_has("[role='alert']", text: "Please contact your platform admin for an invite.")
    end
  end

  describe "create" do
    test "registers new account" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create your account")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Email", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_has("h1", text: "Confirm your email")
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
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

      build_conn()
      |> visit(~p"/register")
      |> assert_has("h1", text: "Create your account")
      |> fill_in("Name", with: "")
      |> fill_in("Email", with: "")
      |> fill_in("Password", with: "")
      |> submit()
      |> assert_path(~p"/register")
      |> assert_has("p", text: "can't be blank", count: 3)

      send_queued_emails()

      refute_email_sent()
    end

    test "doesn't register an account when registrations are disabled" do
      Application.put_env(:nerves_hub, :sign_up_methods, [])

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

    test "confirm account, then sign in" do
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

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
      |> assert_path(~p"/login")
      |> assert_has("[role='alert']", text: "Your email address is confirmed. Sign in to continue.")
      |> fill_in("Email", with: "sgtpepper@geocities.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
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
      Application.put_env(:nerves_hub, :sign_up_methods, [:password, :google])

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
    test "- registering from the emailed invite link confirms the account", %{org: org, user: user} do
      {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)
      %URI{path: path, query: query} = URI.parse(InviteLinks.emailed_url(invite))

      build_conn()
      |> visit("#{path}?#{query}")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs")

      send_queued_emails()

      refute_email_sent(subject: "NervesHub: Confirm your account")
      assert {:ok, %{confirmed_at: %NaiveDateTime{}}} = Accounts.get_user_by_email("joe@example.com")
    end

    test "- registering from the copied invite link joins the org, but signs in only once the address is confirmed", %{
      org: org,
      user: user
    } do
      {:ok, invite} =
        Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> assert_has("h1", text: "Join #{org.name} on #{platform_name}")
      |> refute_has("body", text: "joe@example.com")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_has("h1", text: "Confirm your email")
      |> assert_has("span", text: "We sent a link to the address you were invited at.")
      |> refute_has("body", text: "joe@example.com")
      |> visit(~p"/orgs")
      |> assert_path(~p"/login")

      send_queued_emails()

      # Admins can see invite links, so the address still has to be confirmed
      assert_email_sent(to: [{"", "joe@example.com"}], subject: "NervesHub: Confirm your account")
      assert {:ok, %{confirmed_at: nil} = joe} = Accounts.get_user_by_email("joe@example.com")
      assert {:ok, _org_user} = Accounts.get_org_user(org, joe)

      # don't send email to admin who added the user
      refute_email_sent(subject: "NervesHub: Sgt Pepper has been added to Jeff")
    end

    # The copied link isn't only the invitee's: an admin can register with it
    # and choose the password. Neither registering nor following the
    # confirmation link the invitee is then sent signs anyone in.
    test "- an account registered from the copied link isn't signed in to by registering or by confirming", %{
      org: org,
      user: user
    } do
      {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> fill_in("Name", with: "Not Joe")
      |> fill_in("Password", with: "chosen-by-the-admin")
      |> submit()
      |> visit(~p"/orgs")
      |> assert_path(~p"/login")

      build_conn()
      |> visit(confirmation_path("joe@example.com"))
      |> assert_path(~p"/login")
      |> assert_has("[role='alert']", text: "Your email address is confirmed. Sign in to continue.")
      |> visit(~p"/orgs")
      |> assert_path(~p"/login")

      assert {:ok, %{confirmed_at: %NaiveDateTime{}}} = Accounts.get_user_by_email("joe@example.com")
    end

    test "- the invitee who registered from the copied link signs in once they confirm", %{
      org: org,
      user: user
    } do
      {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

      build_conn()
      |> visit(~p"/invite/#{invite.token}")
      |> fill_in("Name", with: "Sgt Pepper")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> visit(confirmation_path("joe@example.com"))
      |> assert_path(~p"/login")
      |> fill_in("Email", with: "joe@example.com")
      |> fill_in("Password", with: "JohnRingoPaulGeorge")
      |> submit()
      |> assert_path(~p"/orgs")
      |> assert_has("div", text: org.name)

      assert {:ok, %{confirmed_at: %NaiveDateTime{}}} = Accounts.get_user_by_email("joe@example.com")
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

  describe "confirm_email" do
    test "changes the email of the signed in account that asked for it", %{conn: conn, user: user} do
      token = request_email_change(user, "ringo@drums.com")

      conn
      |> visit(~p"/account/confirm-email/#{token}")
      |> assert_path(~p"/account")
      |> assert_has("div", text: "Your email address is now ringo@drums.com.")

      assert Repo.reload(user).email == "ringo@drums.com"
    end

    test "does nothing for a different signed in account", %{conn: conn, user: user} do
      someone_else = Fixtures.user_fixture()
      token = request_email_change(someone_else, "ringo@drums.com")

      conn
      |> visit(~p"/account/confirm-email/#{token}")
      |> assert_path(~p"/account")
      |> assert_has("div", text: "That email change link is invalid or has expired.")

      assert Repo.reload(someone_else).email == someone_else.email
      assert Repo.reload(user).email == user.email
    end

    test "asks a signed out visitor to sign in first", %{user: user} do
      token = request_email_change(user, "ringo@drums.com")

      build_conn()
      |> visit(~p"/account/confirm-email/#{token}")
      |> assert_path(~p"/login")

      assert Repo.reload(user).email == user.email
    end
  end

  defp request_email_change(user, new_email) do
    test_pid = self()

    {:ok, _user, ^new_email} =
      Accounts.update_user(user, %{"email" => new_email, "current_password" => "test_password"}, fn token ->
        send(test_pid, {:token, token})
        token
      end)

    assert_received {:token, token}
    token
  end

  # The path in the confirmation email sent to `email`.
  defp confirmation_path(email) do
    send_queued_emails()

    assert_received {:email, %{to: [{_, ^email}], subject: "NervesHub: Confirm your account", text_body: body}}

    [path] = Regex.run(~r{/confirm/[\w-]+}, body)
    path
  end

  defp signed_in_conn(user) do
    token = Accounts.create_user_session_token(user)

    build_conn()
    |> init_test_session(%{"user_token" => token})
  end
end
