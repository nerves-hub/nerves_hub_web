defmodule NervesHub.Accounts.OrgUserTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    %{user: user, org: org}
  end

  test "with_user/1 preloads user association", %{org: org} do
    query = OrgUser |> where([ou], ou.org_id == ^org.id) |> OrgUser.with_user()
    [org_user] = Repo.all(query)
    assert org_user.user != nil
    assert %User{} = org_user.user
  end
end
