defmodule NervesHubWebCore.AccountsTest do
  use NervesHubWebCore.DataCase, async: true

  alias Ecto.Changeset

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{Org, OrgKey, OrgLimit, User}
  alias NervesHubWebCore.Fixtures

  @required_org_params %{name: "Org"}

  setup do
    user = Fixtures.user_fixture()

    {:ok,
     %{
       user: user
     }}
  end

  test "create_org with required params", %{user: user} do
    {:ok, %Org{} = result_org} = Accounts.create_org(user, @required_org_params)

    assert result_org.name == @required_org_params.name
  end

  test "create_org with duplicate name", %{user: user} do
    {:ok, %Org{}} = Accounts.create_org(user, @required_org_params)
    assert {:error, %Changeset{}} = Accounts.create_org(user, @required_org_params)
  end

  test "create_org_limits with defaults", %{user: user} do
    {:ok, %Org{} = result_org} = Accounts.create_org(user, @required_org_params)
    limits = Accounts.get_org_limit_by_org_id(result_org.id)
    assert limits == %OrgLimit{}
  end

  test "create_org_limits with custom values", %{user: user} do
    org_firmware_size_limit = 1

    {:ok, %Org{} = result_org} = Accounts.create_org(user, @required_org_params)

    limit_params = %{org_id: result_org.id, firmware_size: org_firmware_size_limit}
    {:ok, %OrgLimit{}} = Accounts.create_org_limit(limit_params)

    %{firmware_size: firmware_size_limit} = Accounts.get_org_limit_by_org_id(result_org.id)

    assert firmware_size_limit == org_firmware_size_limit
  end

  test "delete_org_limits", %{user: user} do
    org_firmware_size_limit = 1

    {:ok, %Org{} = result_org} = Accounts.create_org(user, @required_org_params)

    limit_params = %{org_id: result_org.id, firmware_size: org_firmware_size_limit}
    {:ok, %OrgLimit{}} = Accounts.create_org_limit(limit_params)

    %{firmware_size: firmware_size_limit} =
      limits = Accounts.get_org_limit_by_org_id(result_org.id)

    assert firmware_size_limit == org_firmware_size_limit

    {:ok, _} = Accounts.delete_org_limit(limits)
    limits = Accounts.get_org_limit_by_org_id(result_org.id)
    assert limits == %OrgLimit{}
  end

  test "create_org with user" do
    user = Fixtures.user_fixture()
    {:ok, %Org{} = org1} = Accounts.create_org(user, %{name: "An Org"})
    assert org1 in Accounts.get_user_orgs(user)
  end

  test "create_org without required params", %{user: user} do
    assert {:error, %Changeset{}} = Accounts.create_org(user, %{})
  end

  test "create_user adds org with user name" do
    params = %{
      username: "Testy-McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)

    [result_org | _] = Accounts.get_user_orgs(user)

    assert result_org.name == user.username
    assert user.username == params.username
  end

  test "user cannot have two of the same org" do
    params = %{
      username: "Testy-McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)

    [result_org | _] = Accounts.get_user_orgs(user)

    assert {:error, %Changeset{}} = Accounts.add_org_user(result_org, user, %{role: :admin})
  end

  test "add user and remove user from an org" do
    user_params = %{
      username: "Testy-McTesterson",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(user_params)
    {:ok, %Org{} = org_1} = Accounts.create_org(user, %{name: "org1"})

    [default_org, result_org_1 | _] = Accounts.get_user_orgs(user)

    assert default_org.name == user.username
    assert result_org_1.name == org_1.name
    assert user.username == user_params.username

    tmp_user = Fixtures.user_fixture()
    {:ok, %Org{} = org_2} = Accounts.create_org(tmp_user, %{name: "org2"})
    {:ok, _org_user} = Accounts.add_org_user(org_2, user, %{role: :admin})
    user_orgs = Accounts.get_user_orgs(user)

    assert org_1 in user_orgs
    assert org_2 in user_orgs
    assert Enum.count(user_orgs) == 3

    :ok = Accounts.remove_org_user(org_2, user)
    user_orgs = Accounts.get_user_orgs(user)

    assert user_orgs == [default_org, org_1]
  end

  test "Unable to remove last user from org" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    assert {:error, :last_user} = Accounts.remove_org_user(org, user)
  end

  test "Unable to remove user from user org" do
    user = Fixtures.user_fixture()
    [org] = Accounts.get_user_orgs(user)
    assert {:error, :user_org} = Accounts.remove_org_user(org, user)
  end

  describe "authenticate" do
    setup do
      user_params = %{
        orgs: [%{name: "test org 1"}],
        username: "Testy-McTesterson",
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
      username: "Testy-McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)
    [result_org | _] = Accounts.get_user_orgs(user)

    assert result_org.name == user.username
    assert user.username == params.username

    params = %{
      description: "abcd",
      serial: "12345"
    }

    assert {:ok, %Accounts.UserCertificate{}} = Fixtures.user_certificate_fixture(user, params)
  end

  test "cannot create user certificate with duplicate serial" do
    params = %{
      username: "Testy-McTesterson",
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

    assert {:ok, %Accounts.UserCertificate{}} = Fixtures.user_certificate_fixture(user, params)
    assert {:error, %Ecto.Changeset{}} = Fixtures.user_certificate_fixture(user, params)
  end

  test "org_key name must be unique", %{user: user} do
    {:ok, org} = Accounts.create_org(user, @required_org_params)

    {:ok, _} = Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foo"})

    assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", [_ | _]}]}} =
             Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foobar"})
  end

  test "org_key key must be unique", %{user: user} do
    {:ok, org} = Accounts.create_org(user, @required_org_params)

    {:ok, _} = Accounts.create_org_key(%{name: "org's key", org_id: org.id, key: "foo"})

    {:error, %Ecto.Changeset{}} =
      Accounts.create_org_key(%{name: "org's second key", org_id: org.id, key: "foo"})
  end

  test "cannot change org_id of a org_key once created", %{user: user} do
    org = Fixtures.org_fixture(user)
    first_id = org.id
    org_key = Fixtures.org_key_fixture(org)

    other_org = Fixtures.org_fixture(user, %{name: "another org"})

    assert {:ok, %OrgKey{org_id: ^first_id}} =
             Accounts.update_org_key(org_key, %{org_id: other_org.id})
  end

  test "create_org sets type to group", %{user: user} do
    assert {:ok, %Org{type: :group}} = Accounts.create_org(user, %{name: "group-org"})
  end

  test "create_user sets default org to type user" do
    params = %{
      username: "user_with_org",
      org_name: "user_with_org.com",
      email: "user@user_with_org.com",
      password: "asdfasdf"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)
    [result_org | _] = Accounts.get_user_orgs(user)

    assert result_org.type == :user
  end
end
