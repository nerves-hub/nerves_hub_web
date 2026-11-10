defmodule NervesHub.Accounts.StarringTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.Starring
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    %{user: user, org: org, scope: Scope.for_user(user)}
  end

  test "starring an organization lists it as starred", %{user: user, org: org, scope: scope} do
    assert Starring.starred_org_ids(scope) == MapSet.new()

    assert :ok = Starring.star_org(user.id, org.id)
    assert Starring.starred_org_ids(scope) == MapSet.new([org.id])
  end

  test "starring an organization twice keeps one star", %{user: user, org: org, scope: scope} do
    assert :ok = Starring.star_org(user.id, org.id)
    assert :ok = Starring.star_org(user.id, org.id)

    assert Starring.starred_org_ids(scope) == MapSet.new([org.id])
  end

  test "unstarring an organization takes its star away", %{user: user, org: org, scope: scope} do
    :ok = Starring.star_org(user.id, org.id)

    assert {1, nil} = Starring.unstar_org(user.id, org.id)
    assert Starring.starred_org_ids(scope) == MapSet.new()

    assert {0, nil} = Starring.unstar_org(user.id, org.id)
  end

  test "a star is only the user's own", %{user: user, org: org} do
    other = Fixtures.user_fixture()
    {:ok, _} = Accounts.add_org_user(org, other, %{role: :view})

    :ok = Starring.star_org(user.id, org.id)

    assert Starring.starred_org_ids(Scope.for_user(other)) == MapSet.new()
  end

  test "leaving an organization takes the star away", %{user: user, org: org, scope: scope} do
    other = Fixtures.user_fixture()
    {:ok, _} = Accounts.add_org_user(org, other, %{role: :admin})
    :ok = Starring.star_org(user.id, org.id)

    :ok = Accounts.remove_org_user(org, user)

    assert Starring.starred_org_ids(scope) == MapSet.new()
  end

  test "an organization that doesn't exist can't be starred", %{user: user} do
    assert {:error, %Ecto.Changeset{}} = Starring.star_org(user.id, -1)
  end
end
