defmodule NervesHubCore.AccountsTest do
  use NervesHubCore.DataCase

  alias Ecto.Changeset

  alias NervesHubCore.Accounts
  alias NervesHubCore.Fixtures
  alias NervesHubCore.Repo

  @required_tenant_params %{name: "Tenant"}

  test "create_tenant with required params" do
    {:ok, %Accounts.Tenant{} = result_tenant} = Accounts.create_tenant(@required_tenant_params)

    assert result_tenant.name == @required_tenant_params.name
  end

  test "create_tenant without required params" do
    assert {:error, %Changeset{}} = Accounts.create_tenant(%{})
  end

  test "create_tenant_with_user with valid params" do
    params = %{
      name: "Testy McTesterson",
      tenant_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_tenant = %Accounts.Tenant{name: params.tenant_name}
    {:ok, %Accounts.Tenant{} = result_tenant} = Accounts.create_tenant_with_user(params)

    [user | _] = result_tenant |> Repo.preload(:users) |> Map.get(:users)

    assert result_tenant.name == target_tenant.name
    assert user.name == params.name
  end

  test "create_tenant_with_user with missing params" do
    params = %{
      name: "Testy McTesterson",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    assert {:error, %Changeset{}} = Accounts.create_tenant_with_user(params)
  end

  test "create_tenant_with_user_with_certificate with valid params" do
    params = %{
      name: "Testy McTesterson",
      tenant_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    target_tenant = %Accounts.Tenant{name: params.tenant_name}
    {:ok, %Accounts.Tenant{} = result_tenant} = Accounts.create_tenant_with_user(params)

    [user | _] = result_tenant |> Repo.preload(:users) |> Map.get(:users)

    assert result_tenant.name == target_tenant.name
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
      tenant_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %Accounts.Tenant{} = result_tenant} = Accounts.create_tenant_with_user(params)

    [user | _] = result_tenant |> Repo.preload(:users) |> Map.get(:users)

    params = %{
      description: "abcd",
      serial: "12345"
    }

    {:ok, _cert} = Accounts.create_user_certificate(user, params)
    {:error, %Ecto.Changeset{}} = Accounts.create_user_certificate(user, params)
  end

  test "tenant_key name must be unique" do
    {:ok, tenant} = Accounts.create_tenant(@required_tenant_params)

    {:ok, _} =
      Accounts.create_tenant_key(%{name: "tenant's key", tenant_id: tenant.id, key: "foo"})

    {:error, %Ecto.Changeset{errors: [name: {"has already been taken", []}]}} =
      Accounts.create_tenant_key(%{name: "tenant's key", tenant_id: tenant.id, key: "foobar"})
  end

  test "tenant_key key must be unique" do
    {:ok, tenant} = Accounts.create_tenant(@required_tenant_params)

    {:ok, _} =
      Accounts.create_tenant_key(%{name: "tenant's key", tenant_id: tenant.id, key: "foo"})

    {:error, %Ecto.Changeset{}} =
      Accounts.create_tenant_key(%{name: "tenant's second key", tenant_id: tenant.id, key: "foo"})
  end

  test "cannot change tenant_id of a tenant_key once created" do
    tenant = Fixtures.tenant_fixture()
    first_id = tenant.id
    tenant_key = Fixtures.tenant_key_fixture(tenant)

    other_tenant = Fixtures.tenant_fixture()

    assert {:ok, %Accounts.TenantKey{tenant_id: ^first_id}} =
             Accounts.update_tenant_key(tenant_key, %{tenant_id: other_tenant.id})
  end
end
