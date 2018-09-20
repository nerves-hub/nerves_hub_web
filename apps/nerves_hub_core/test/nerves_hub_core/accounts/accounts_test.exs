defmodule NervesHubCore.AccountsTest do
  use NervesHubCore.DataCase, async: true

  alias Ecto.Changeset

  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.{Org, OrgKey, OrgLimit, User}
  alias NervesHubCore.Fixtures

  @required_org_params %{name: "Org"}

  test "create_org with required params" do
    {:ok, %Org{} = result_org} = Accounts.create_org(@required_org_params)

    assert result_org.name == @required_org_params.name
  end

  test "create_org with duplicate name" do
    {:ok, %Org{}} = Accounts.create_org(@required_org_params)
    assert {:error, %Changeset{}} = Accounts.create_org(@required_org_params)
  end

  test "create_org_limits with defaults" do
    {:ok, %Org{} = result_org} = Accounts.create_org(@required_org_params)
    {:ok, limits} = Accounts.get_org_limit_by_org_id(result_org.id)
    assert limits == %OrgLimit{}
  end

  test "create_org_limits with custom values" do
    org_firmware_size_limit = 1

    {:ok, %Org{} = result_org} = Accounts.create_org(@required_org_params)

    limit_params = %{org_id: result_org.id, firmware_size: org_firmware_size_limit}
    {:ok, %OrgLimit{}} = Accounts.create_org_limit(limit_params)

    {:ok, %{firmware_size: firmware_size_limit}} = Accounts.get_org_limit_by_org_id(result_org.id)

    assert firmware_size_limit == org_firmware_size_limit
  end

  test "delete_org_limits" do
    org_firmware_size_limit = 1

    {:ok, %Org{} = result_org} = Accounts.create_org(@required_org_params)

    limit_params = %{org_id: result_org.id, firmware_size: org_firmware_size_limit}
    {:ok, %OrgLimit{}} = Accounts.create_org_limit(limit_params)

    {:ok, %{firmware_size: firmware_size_limit} = limits} =
      Accounts.get_org_limit_by_org_id(result_org.id)

    assert firmware_size_limit == org_firmware_size_limit

    {:ok, _} = Accounts.delete_org_limit(limits)
    {:ok, limits} = Accounts.get_org_limit_by_org_id(result_org.id)
    assert limits == %OrgLimit{}
  end

  test "create_org with user" do
    {:ok, %Org{} = org1} = Accounts.create_org(%{name: "An Org"})
    user = Fixtures.user_fixture(org1)

    {:ok, %Org{} = org2} = Accounts.create_org(%{name: "Another Org", users: [user]})
    {:ok, user_with_orgs} = Accounts.get_user_with_all_orgs(user.id)

    assert org2.id in (user_with_orgs.orgs |> Enum.map(fn x -> x.id end))
  end

  test "create_org without required params" do
    assert {:error, %Changeset{}} = Accounts.create_org(%{})
  end

  test "cannot modify users_orgs through Org.update_changeset" do
    {:ok, org} = Accounts.create_org(%{name: "foo"})
    assert {:error, %Changeset{}} = Accounts.update_org(org, %{users: []})
  end

  test "create_user with org" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Org{name: params.org_name}

    {:ok, %User{} = user} = Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

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

    target_org = %Org{name: params.org_name}

    {:ok, %User{} = user} = Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

    [result_org | _] = user.orgs

    assert {:error, %Changeset{}} = Accounts.add_user_to_org(user, result_org)
  end

  test "create_user with no org" do
    params = %{
      name: "Testy McTesterson",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    assert {:error, %Changeset{}} = Accounts.create_user(params)
  end

  test "cannot change orgs with update_user/2" do
    org = Fixtures.org_fixture()
    user = Fixtures.user_fixture(org)

    new_org = Fixtures.org_fixture(%{name: "new org"})

    assert {:error, %Changeset{errors: [orgs: _]}} =
             Accounts.update_user(user, %{orgs: [org, new_org]})
  end

  test "add user and remove user from an org" do
    {:ok, %Org{} = org_1} = Accounts.create_org(%{name: "org1"})
    {:ok, %Org{} = org_2} = Accounts.create_org(%{name: "org2"})

    user_params = %{
      orgs: [org_1],
      name: "Testy McTesterson",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(user_params)

    [result_org_1 | _] = user.orgs

    assert result_org_1.name == org_1.name
    assert user.name == user_params.name

    {:ok, user} = Accounts.add_user_to_org(user, org_2)
    assert org_1 in user.orgs
    assert org_2 in user.orgs
    assert Enum.count(user.orgs) == 2

    {:ok, user} = Accounts.remove_user_from_org(user, org_2)

    assert user.orgs == [org_1]
  end

  describe "authenticate" do
    setup do
      user_params = %{
        orgs: [%{name: "test org 1"}],
        name: "Testy McTesterson",
        email: "testy@mctesterson.com",
        password: "test_password"
      }

      {:ok, user} = Accounts.create_user(user_params)

      {:ok, %{user: user}}
    end

    test "with valid credentials", %{user: user} do
      target_email = user.email

      assert {:ok, %User{email: ^target_email, orgs: [%Org{}]}} =
               Accounts.authenticate(user.email, user.password)
    end

    test "with invalid credentials", %{user: user} do
      assert {:error, :authentication_failed} =
               Accounts.authenticate(user.email, "wrong password")
    end

    test "with non existent user email" do
      assert {:error, :authentication_failed} =
               Accounts.authenticate("non existent email", "wrong password")
    end
  end

  test "create_org_with_user_with_certificate with valid params" do
    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_org = %Org{name: params.org_name}

    {:ok, %User{} = user} = Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

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

    target_org = %Org{name: params.org_name}

    {:ok, %User{} = user} = Accounts.create_user(%{orgs: [target_org]} |> Enum.into(params))

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

    other_org = Fixtures.org_fixture(%{name: "another org"})

    assert {:ok, %OrgKey{org_id: ^first_id}} =
             Accounts.update_org_key(org_key, %{org_id: other_org.id})
  end
end
