defmodule NervesHubWeb.Live.Org.UsersTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Fixtures

  describe "users" do
    test "all users of the org are listed", %{conn: conn, org: org} do
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> tap(fn conn ->
        for org_user <- Accounts.get_org_users(org) do
          assert_has(conn, "td", text: org_user.user.username)
        end
      end)
    end

    test "you can't remove yourself from the org", %{conn: conn, org: org, user: user} do
      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> assert_has("td", text: user.username)
      |> refute_has("a[phx-value-user_id=\"#{user.id}\"]", text: "Delete")
    end

    test "update org user role", %{conn: conn, org: org} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users/#{org_user.user_id}/edit")
      |> assert_has("h1", text: org_user.user.username)
      |> select("Admin", from: "Role")
      |> click_button("Update")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "Role updated")
    end

    test "delete org user", %{conn: conn, org: org, user: user} do
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h1", text: "Users")
      |> click_link("a[phx-value-user_id=\"#{org_user.user_id}\"]", "Delete")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User removed")

      assert_email_sent(
        subject: "User #{user.username} removed #{org_user.user.username} from #{org.name}"
      )
    end
  end

  describe "invites" do
    test "sends invite to user if they aren't registed", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h1", text: "Add New User")
      |> fill_in("Email", with: "josh@mrjosh.com")
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been invited")
      |> assert_has("h1", text: "Outstanding Invites")
      |> assert_has("td", text: "josh@mrjosh.com")

      assert_email_sent(subject: "Hi from NervesHub!")
    end

    test "adds user if they are already registered", %{conn: conn, org: org} do
      morejosh = Fixtures.user_fixture(%{name: "morejosh"})

      conn
      |> visit("/org/#{org.name}/settings/users/invite")
      |> assert_has("h1", text: "Add New User")
      |> fill_in("Email", with: morejosh.email)
      |> click_button("Send Invitation")
      |> assert_path("/org/#{org.name}/settings/users")
      |> assert_has("div", text: "User has been added to #{org.name}")
      |> refute_has("h1", text: "Outstanding Invites")
      |> assert_has("td", text: morejosh.email)

      assert_email_sent(subject: "Welcome to #{org.name}")
    end

    test "rescind unaccepted invite", %{conn: conn, org: org, user: user} do
      {:ok, _} = Accounts.invite(%{"email" => "josh@mrjosh.com", "role" => "view"}, org, user)

      conn
      |> visit("/org/#{org.name}/settings/users")
      |> click_link("Rescind")
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
      |> assert_has("span", text: "is already member")

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
        |> assert_has("h1", text: "Outstanding Invites")
        |> assert_has("td", text: "josh@mrjosh.com")

      invite
      |> Accounts.Invite.changeset(%{accepted: true})
      |> NervesHub.Repo.update()

      conn
      |> click_link("Rescind")
      |> refute_has("td", text: "josh@mrjosh.com")
      |> assert_has("div", text: "Invite couldn't be rescinded as the invite has been accepted.")

      refute_email_sent()
    end
  end
end
