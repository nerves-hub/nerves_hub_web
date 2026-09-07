defmodule NervesHub.Accounts.OrgTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    _org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    %{user: user, org: org}
  end

  test "with_org_keys/1 preloads org_keys on an Org struct", %{org: org} do
    loaded = Org.with_org_keys(org)
    assert is_list(loaded.org_keys)
    refute Enum.empty?(loaded.org_keys)
  end

  test "with_org_keys/1 preloads org_keys on a query", %{org: org} do
    query = Org |> where([o], o.id == ^org.id) |> Org.with_org_keys()
    [loaded] = Repo.all(query)
    assert is_list(loaded.org_keys)
    refute Enum.empty?(loaded.org_keys)
  end
end
