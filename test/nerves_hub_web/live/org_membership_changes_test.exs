defmodule NervesHubWeb.Live.OrgMembershipChangesTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Fixtures

  # The pages a member has open in an org were mounted under their old role.
  # These change the membership the way another admin would, from outside the
  # open page.

  setup %{org: org} do
    # Another admin, so the org still has one whatever happens to this member.
    {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :admin})

    :ok
  end

  test "a demoted member's open page mounts again under their new role", %{conn: conn, org: org, user: user} do
    session =
      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("form[phx-change=change_role]")

    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, _} = Accounts.change_org_user_role(org_user, :view)

    session
    |> assert_has("div", text: "Your role in #{org.name} has changed.", timeout: 1000)
    |> assert_path("/org/#{org.name}/settings/users")
    |> refute_has("form[phx-change=change_role]")
  end

  test "a removed member's open page sends them back to their orgs", %{conn: conn, org: org, user: user} do
    session =
      conn
      |> visit("/org/#{org.name}/settings/users")
      |> assert_has("h2", text: "Members")

    :ok = Accounts.remove_org_user(org, user)

    session
    |> assert_has("div", text: "You're no longer a member of #{org.name}.", timeout: 1000)
    |> assert_path("/orgs")
  end
end
