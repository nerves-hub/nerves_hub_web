defmodule NervesHubCore.AccountsTest do
  use NervesHubCore.DataCase

  alias Ecto.Changeset

  alias NervesHubCore.Accounts
  alias NervesHubCore.Fixtures

  @required_org_params %{name: "Org"}

  test "create_org with required params" do
    {:ok, %Accounts.Org{} = result_org} = Accounts.create_org(@required_org_params)

    assert result_org.name == @required_org_params.name
  end

  test "create_org without required params" do
    assert {:error, %Changeset{}} = Accounts.create_org(%{})
  end

  test "create_user with org" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Accounts.Org{name: params.org_name}

    {:ok, %Accounts.User{} = user} =
      Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

    [result_org | _] = user.orgs

    assert result_org.name == target_org.name
    assert user.name == params.name
  end

  test "user cannot have two of the same org" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Accounts.Org{name: params.org_name}

    {:ok, %Accounts.User{} = user} =
      Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

    [result_org | _] = user.orgs

    {:ok, user} = Accounts.update_user(user, %{orgs: [result_org, result_org]})
    assert Enum.count(user.orgs) == 1
  end

  test "create_user with no org" do
    params = %{
      name: "Testy McTesterson",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    assert {:error, %Changeset{}} = Accounts.create_user(params)
  end

  test "create_org_with_user_with_certificate with valid params" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Accounts.Org{name: params.org_name}

    {:ok, %Accounts.User{} = user} =
      Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

    [result_org | _] = user.orgs

    assert result_org.name == target_org.name
    assert user.name == params.name

    params = %{
      description: "abcd",
      serial: "12345"
    }

    assert {:ok, _cert} = Accounts.create_user_certificate(user, params)
  end

  test "cannot create user certificate with duplicate serial" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Accounts.Org{name: params.org_name}

    {:ok, %Accounts.User{} = user} =
      Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

    params = %{
      description: "abcd",
      serial: "12345"
    }

    {:ok, _cert} = Accounts.create_user_certificate(user, params)
    {:error, %Ecto.Changeset{}} = Accounts.create_user_certificate(user, params)
  end

  test "org_key name must be unique" do
    {:ok, org} = Accounts.create_org(@required_org_params)

    {:ok, _} = Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foo"})

    {:error, %Ecto.Changeset{errors: [name: {"has already been taken", []}]}} =
      Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foobar"})
  end

  test "org_key key must be unique" do
    {:ok, org} = Accounts.create_org(@required_org_params)

    {:ok, _} = Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foo"})

    {:error, %Ecto.Changeset{}} =
      Accounts.create_org_key(%{name: "org's second key", org_id: org.id, key: "foo"})
  end

  test "cannot change org_id of a org_key once created" do
    org = Fixtures.org_fixture()
    first_id = org.id
    org_key = Fixtures.org_key_fixture(org)

    other_org = Fixtures.org_fixture()

    assert {:ok, %Accounts.OrgKey{org_id: ^first_id}} =
             Accounts.update_org_key(org_key, %{org_id: other_org.id})
  end
end
