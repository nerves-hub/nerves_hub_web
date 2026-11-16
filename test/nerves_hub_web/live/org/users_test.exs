defmodule NervesHubWeb.Live.Org.UsersTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Ecto.Query, only: [where: 3]
  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.InviteLinks

  describe "users" do
    test "all users of the org are listed", %{conn: conn, org: org} do
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Members")
      |> tap(fn conn ->
        for org_user <- Accounts.get_org_users(org) do
          assert_has(conn, "#member-#{org_user.user_id}", text: org_user.user.name)
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
      |> assert_has("h2", text: "Members")
      |> assert_has("#member-#{user.id}", text: user.name)
      |> refute_has("#remove-user-#{user.id}")
    end

    test "you can remove yourself from the org, if you are an admin but not the only one", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, _org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :admin})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Members")
      |> assert_has("#member-#{user.id}", text: user.name)
      |> click_button("#remove-user-#{user.id}", "Leave organization")
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
      |> assert_has("h2", text: "Members")
      |> assert_has("#member-#{user.id}", text: user.name)
      |> click_button("#remove-user-#{user.id}", "Leave organization")
      |> assert_path(~p"/orgs")
      |> assert_has("div", text: "You have removed yourself from the #{org.name} org")
    end

    test "update org user role", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> assert_has("h2", text: org_user.user.name)
      |> select("Role", option: "Admin", exact: false)
      |> click_button("Update")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "Role updated")
    end

    test "an admin changes a member's role from their row", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> within("#member-#{org_user.user_id}", fn session ->
        select(session, "Role for #{org_user.user.name}", option: "Manage")
      end)
      |> assert_has("div", text: "#{org_user.user.name} is now Manage")

      assert {:ok, %{role: :manage}} = Accounts.get_org_user(org, org_user.user)
    end

    test "your own role isn't offered for change", %{conn: conn, org: org, user: user} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("#role-#{org_user.user_id}")
      |> refute_has("#role-#{user.id}")
      |> assert_has("#member-#{user.id}", text: "Admin")
    end

    test "a member who can't update roles sees them as text", %{org: org, user: user} do
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})

      build_conn()
      |> init_test_session(%{"user_token" => Accounts.create_user_session_token(viewer)})
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("#member-#{user.id}", text: "Admin")
      |> refute_has("select")
    end

    test "members are listed admins first, then by name, with a count of each role", %{conn: conn, org: org, user: user} do
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(%{name: "Zed Viewer"}), %{role: :view})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(%{name: "Amy Manager"}), %{role: :manage})

      session = visit(conn, "/org/#{org.name}/settings/users")

      rows =
        session.view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#members [role=row][id^=member-]")
        |> Enum.map(&LazyHTML.text/1)

      position = fn name -> Enum.find_index(rows, &String.contains?(&1, name)) end

      assert position.(user.name) == 0
      assert position.("Amy Manager") == 1
      assert position.("Zed Viewer") == 2

      assert_has(session, "#members-roles", text: "1 admin · 1 manage · 1 view")
    end

    test "delete org user", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Members")
      |> assert_has("nav a[aria-current='page']", text: "Users 2")
      |> click_button("#remove-user-#{org_user.user_id}", "Remove from organization")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User removed")
      |> assert_has("nav a[aria-current='page']", text: "Users 1")

      send_queued_emails()

      # don't send email to admin who added the user
      refute_email_sent()
    end

    # Only the index page loads the admin count, so these check the event
    # still works from the other pages of the same LiveView.
    test "delete org user from the edit page", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> unwrap(&render_click(&1, "delete_org_user", %{"user_id" => org_user.user_id}))
      |> assert_has("div", text: "User removed")

      assert Accounts.get_org_user(org, org_user.user) == {:error, :not_found}
    end

    test "delete org user from the invite page", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> unwrap(&render_click(&1, "delete_org_user", %{"user_id" => org_user.user_id}))
      |> assert_has("div", text: "User removed")

      assert Accounts.get_org_user(org, org_user.user) == {:error, :not_found}
    end

    test "the only admin can't remove themself from the edit page either", %{conn: conn, org: org, user: user} do
      session = visit(conn, "/org/#{org.name}/settings/users/#{user.id}/edit")

      assert render_click(session.view, "delete_org_user", %{"user_id" => user.id}) =~
               "Sorry. You were denied access. Please check your role or contact your support."

      assert {:ok, _} = Accounts.get_org_user(org, user)
    end
  end

  describe "custom roles" do
    test "a member can be given one of the org's roles", %{conn: conn, org: org} do
      Fixtures.org_role_fixture(org, %{name: "Release Manager"})
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> select("Role", option: "Release Manager")
      |> click_button("Update")
      |> assert_has("div", text: "Role updated")
      |> assert_has("#member-#{org_user.user_id} option[selected]", text: "Release Manager")

      assert {:ok, %{role: nil, org_role: %{name: "Release Manager"}}} = Accounts.get_org_user(org, org_user.user_id)
    end

    test "the edit form starts on the member's custom role", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Release Manager"})
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> assert_has("option[selected]", text: "Release Manager")
    end

    test "an invite can offer one of the org's roles", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Release Manager"})

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> fill_in("Email", with: "josh@mrjosh.com")
      |> select("Role", option: "Release Manager", exact: false)
      |> click_button("Send Invitation")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("#invites", text: "Invited as Release Manager")

      assert [%{role: nil, org_role_id: org_role_id}] = Accounts.get_invites_for_org(org)
      assert org_role_id == role.id
    end

    test "the members list's role menu can give one of the org's roles", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Release Manager"})
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> within("#role-form-#{org_user.user_id}", fn session ->
        select(session, "Role for #{org_user.user.name}", option: "Release Manager")
      end)
      |> assert_has("div", text: "#{org_user.user.name} is now Release Manager")

      assert {:ok, %{role: nil, org_role_id: org_role_id}} = Accounts.get_org_user(org, org_user.user_id)
      assert org_role_id == role.id
    end

    test "the members list's role menu can't give another org's role", %{conn: conn, org: org} do
      other_org = Fixtures.org_fixture(Fixtures.user_fixture(), %{name: "OtherOrg"})
      other_role = Fixtures.org_role_fixture(other_org, %{name: "Elsewhere"})
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> unwrap(
        &render_change(&1, "change_role", %{"user_id" => org_user.user_id, "role" => "custom:#{other_role.id}"})
      )
      |> assert_has("div", text: "Error updating role")

      assert {:ok, %{role: :view, org_role_id: nil}} = Accounts.get_org_user(org, org_user.user_id)
    end
  end

  describe "invites" do
    test "sends invite to user if they aren't registered", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h2", text: "Add New User")
      |> fill_in("Email", with: "josh@mrjosh.com")
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("h2", text: "Waiting to join")
      |> assert_has("#invites", text: "josh@mrjosh.com")

      send_queued_emails()

      invite = Repo.get_by!(Invite, email: "josh@mrjosh.com")

      # The email's link has the key that confirms the address, which the
      # link admins can copy doesn't
      assert_email_sent(fn email ->
        assert email.subject == "NervesHub: You have been invited to join Jeff"
        assert [_, key] = Regex.run(~r{/invite/#{invite.token}\?key=([\w.-]+)}, email.text_body)
        assert InviteLinks.emailed_key?(invite, key)
      end)
    end

    test "the pending invite lists the role and who sent it", %{conn: conn, org: org, user: user} do
      {:ok, _} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "manage"}, org, user)

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Waiting to join")
      |> assert_has("#invites", text: "josh@mrjosh.com")
      |> assert_has("#invites", text: "Invited as Manage by #{user.name}")
    end

    test "invites, rather than adds, a user who is already registered", %{conn: conn, org: org} do
      josh_again = Fixtures.user_fixture(%{name: "Josh Again"})

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h2", text: "Add New User")
      |> fill_in("Email", with: josh_again.email)
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("h2", text: "Waiting to join")
      |> assert_has("#invites", text: josh_again.email)

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
        |> assert_has("h2", text: "Waiting to join")
        # the link rides on the copy button rather than being printed in the page
        |> refute_has("code", text: invite.token)
        |> assert_has("button[data-copy-value$='/invite/#{invite.token}']", text: "Copy link")

      session
      |> click_button("Resend")
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
      |> assert_has("h2", text: "Waiting to join")
      |> assert_has("button[disabled]", text: "Copy link")
      |> assert_has("button[disabled]", text: "Resend")
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
      |> refute_has("#invites")
    end

    test "displays errors if the user is already part of the org", %{
      conn: conn,
      org: org,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h2", text: "Add New User")
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
        |> assert_has("#invites", text: "josh@mrjosh.com")

      # the invitee declines while the admin still has the page open
      {:ok, _} = Accounts.decline_invite(invite)

      conn
      |> click_button("Rescind")
      |> refute_has("#invites", text: "josh@mrjosh.com")
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
        |> assert_has("h2", text: "Waiting to join")
        |> assert_has("#invites", text: "josh@mrjosh.com")

      invite
      |> Accounts.Invite.changeset(%{accepted: true})
      |> NervesHub.Repo.update()

      conn
      |> click_button("Rescind")
      |> refute_has("#invites", text: "josh@mrjosh.com")
      |> assert_has("div", text: "Invite couldn't be rescinded as it has already been accepted.")

      send_queued_emails()

      refute_email_sent()
    end
  end
end
