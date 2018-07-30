defmodule NervesHubCore.AccountsTest do
  use NervesHubCore.DataCase

  alias NervesHubCore.Repo
  alias NervesHubCore.Accounts
  alias Ecto.Changeset

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
end
