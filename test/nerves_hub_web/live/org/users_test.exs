defmodule NervesHubWeb.Live.Org.UsersTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Ecto.Query, only: [where: 3]
  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "users" do
    test "all users of the org are listed", %{conn: conn, org: org} do
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> tap(fn conn ->
        for org_user <- Accounts.get_org_users(org) do
          assert_has(conn, "td", text: org_user.user.name)
        end
      end)
    end

    test "you can't remove yourself from the org, if you are an admin and the only admin", %{
      conn: conn,
      org: org,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> assert_has("td", text: user.name)
      |> refute_has("a[phx-value-user_id=\"#{user.id}\"]", text: "Remove")
    end

    test "you can remove yourself from the org, if you are an admin but not the only one", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, _org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :admin})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> assert_has("td", text: user.name)
      |> click_button("#remove-user-#{user.id}", "Remove")
      |> assert_path(~p"/orgs")
      |> assert_has("div", text: "You have removed yourself from the #{org.name} org")
    end

    test "you can remove yourself from the org, if you are not an admin", %{conn: conn, org: org, user: user} do
      {:ok, _org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :admin})

      {1, _} =
        OrgUser
        |> where([ou], ou.org_id == ^org.id)
        |> where([ou], ou.user_id == ^user.id)
        |> Repo.update_all(set: [role: :view])

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> assert_has("td", text: user.name)
      |> click_button("#remove-user-#{user.id}", "Remove")
      |> assert_path(~p"/orgs")
      |> assert_has("div", text: "You have removed yourself from the #{org.name} org")
    end

    test "update org user role", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> assert_has("h1", text: org_user.user.name)
      |> select("Role", option: "Admin", exact: false)
      |> click_button("Update")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "Role updated")
    end

    test "clicking edit button navigates to edit page", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> assert_has("td", text: org_user.user.name)
      |> click_link("Edit")
      |> assert_path("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> assert_has("h1", text: org_user.user.name)
      |> assert_has("label", text: "Role")
    end

    test "delete org user", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> click_link("button[phx-value-user_id=\"#{org_user.user_id}\"]", "Remove")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User removed")

      send_queued_emails()

      # don't send email to admin who added the user
      refute_email_sent()
    end
  end

  describe "invites" do
    test "sends invite to user if they aren't registered", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h1", text: "Add New User")
      |> fill_in("Email", with: "josh@mrjosh.com")
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("h2", text: "Outstanding Invites")
      |> assert_has("td", text: "josh@mrjosh.com")

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: You have been invited to join Jeff")
    end

    test "the pending invite lists the role and who sent it", %{conn: conn, org: org, user: user} do
      {:ok, _} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "manage"}, org, user)

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Outstanding Invites")
      |> assert_has("td", text: "josh@mrjosh.com")
      |> assert_has("td", text: "manage")
      |> assert_has("td", text: user.name)
    end

    test "invites, rather than adds, a user who is already registered", %{conn: conn, org: org} do
      josh_again = Fixtures.user_fixture(%{name: "Josh Again"})

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h1", text: "Add New User")
      |> fill_in("Email", with: josh_again.email)
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("h2", text: "Outstanding Invites")
      |> assert_has("td", text: josh_again.email)

      # they are not a member until they accept
      assert Accounts.get_org_user(org, josh_again) == {:error, :not_found}

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: You have been invited to join Jeff")
    end

    test "displays an error when the invitee already has a pending invite", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, _} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> fill_in("Email", with: "josh@mrjosh.com")
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users/invite")
      |> assert_has("span", text: "has already been invited to this organization")

      send_queued_emails()

      refute_email_sent()
    end

    test "an admin can copy the invite link and resend the invite", %{conn: conn, org: org, user: user} do
      {:ok, invite} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      session =
        conn
        |> visit("/org/#{org.name}/settings/users")
        |> assert_has("h2", text: "Outstanding Invites")
        # the link rides on the copy button rather than being printed in the page
        |> refute_has("code", text: invite.token)
        |> assert_has("button[data-copy-value$='/invite/#{invite.token}']", text: "Copy invite link")

      session
      |> click_button("Resend invite")
      |> assert_has("div", text: "Invite resent to josh@mrjosh.com")

      # resending rotates the token, so the link that leaked stops working
      resent = Repo.reload(invite)
      refute resent.token == invite.token
      assert Accounts.get_valid_invite(invite.token) == {:error, :invite_not_found}
      assert {:ok, _} = Accounts.get_valid_invite(resent.token)

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: You have been invited to join #{org.name}")
    end

    test "resending puts an expired invite back in play", %{org: org, user: user} do
      {:ok, invite} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      three_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -3, :day)

      {1, _} =
        Accounts.Invite
        |> where([i], i.id == ^invite.id)
        |> Repo.update_all(set: [inserted_at: three_days_ago, updated_at: three_days_ago])

      assert Accounts.get_valid_invite(invite.token) == {:error, :invite_not_found}

      {:ok, resent} = Accounts.resend_invite(org, invite.token)

      assert {:ok, _} = Accounts.get_valid_invite(resent.token)
    end

    test "a non admin gets disabled invite actions and never sees the token", %{org: org, user: user} do
      {:ok, invite} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      viewer = Fixtures.user_fixture(%{name: "Nosy Parker"})
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})
      token = Accounts.create_user_session_token(viewer)

      build_conn()
      |> init_test_session(%{"user_token" => token})
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Outstanding Invites")
      |> assert_has("button[disabled]", text: "Copy invite link")
      |> assert_has("button[disabled]", text: "Resend invite")
      |> assert_has("button[disabled]", text: "Rescind")
      # the invite token is the credential, and it hides in attributes rather
      # than in the text, so check the attributes that would carry it
      |> refute_has("[data-copy-value]")
      |> refute_has("[phx-value-invite_token]")
      |> refute_has("body", text: invite.token)
    end

    test "rescind unaccepted invite", %{conn: conn, org: org, user: user} do
      {:ok, _} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> click_button("Rescind")
      |> assert_has("div", text: "Invite rescinded")
      |> assert_path("/org/#{org.name}/settings/users")
      |> refute_has("h1", text: "Outstanding Invites")
    end

    test "displays errors if the user is already part of the org", %{
      conn: conn,
      org: org,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h1", text: "Add New User")
      |> fill_in("Email", with: user.email)
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users/invite")
      |> assert_has("p", text: "Something went wrong, please check the errors below.")
      |> assert_has("span", text: "is already a member of this organization")

      send_queued_emails()

      refute_email_sent()
    end

    test "displays an error if you rescind an invite after it was declined", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, invite} =
        Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      conn =
        conn
        |> visit("/org/#{org.name}/settings/users")
        |> assert_has("td", text: "josh@mrjosh.com")

      # the invitee declines while the admin still has the page open
      {:ok, _} = Accounts.decline_invite(invite)

      conn
      |> click_button("Rescind")
      |> refute_has("td", text: "josh@mrjosh.com")
      |> assert_has("div", text: "Invite couldn't be rescinded as it has already been declined.")

      refute_email_sent()
    end

    test "displays an error if you rescind an invite after it was accepted", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, invite} =
        Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      conn =
        conn
        |> visit("/org/#{org.name}/settings/users")
        |> assert_has("h2", text: "Outstanding Invites")
        |> assert_has("td", text: "josh@mrjosh.com")

      invite
      |> Accounts.Invite.changeset(%{accepted: true})
      |> NervesHub.Repo.update()

      conn
      |> click_button("Rescind")
      |> refute_has("td", text: "josh@mrjosh.com")
      |> assert_has("div", text: "Invite couldn't be rescinded as it has already been accepted.")

      send_queued_emails()

      refute_email_sent()
    end
  end
end
