defmodule NervesHub.Products.ApiKeysTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  describe "create/3" do
    test "returns the key once and stores only its hash", %{user: user, product: product} do
      assert {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})

      assert "nhpk_" <> _ = token
      assert api_key.name == "CI deploys"
      assert api_key.role == :manage
      assert api_key.created_by_id == user.id
      assert api_key.org_id == product.org_id

      stored = Repo.reload!(api_key)
      assert byte_size(stored.token_hash) == 64
      assert ApiKey.hash_token(token) == {:ok, stored.token_hash}
    end

    test "can be given one of the org's custom roles", %{user: user, org: org, product: product} do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer", permissions: ["deployment_group:update"]})

      assert {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      assert is_nil(api_key.role)
      assert api_key.org_role_id == role.id
      assert ApiKey.assigned_role(api_key).id == role.id
    end

    test "requires a name", %{user: user, product: product} do
      assert {:error, changeset} = ApiKeys.create(product, user, %{"name" => "  ", "role" => "view"})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires exactly one kind of role", %{user: user, org: org, product: product} do
      role = Fixtures.org_role_fixture(org)

      assert {:error, neither} = ApiKeys.create(product, user, %{"name" => "CI"})
      assert "can't be blank" in errors_on(neither).role

      assert {:error, both} =
               ApiKeys.create(product, user, %{"name" => "CI", "role" => "view", "org_role_id" => role.id})

      assert "can't be both a built-in and a custom role" in errors_on(both).role
    end

    test "has no admin role", %{user: user, product: product} do
      assert {:error, changeset} = ApiKeys.create(product, user, %{"name" => "Too much", "role" => "admin"})

      # `errors_on/1` can't interpolate an Ecto.Enum cast error's options.
      assert {"is invalid", _opts} = changeset.errors[:role]
    end

    test "refuses a role from another organization", %{user: user, product: product} do
      other_org = Fixtures.org_fixture(user, %{name: "other-org"})
      other_role = Fixtures.org_role_fixture(other_org)

      assert {:error, changeset} =
               ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => other_role.id})

      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)
    end

    test "refuses a role that has been deleted", %{user: user, org: org, product: product} do
      role = Fixtures.org_role_fixture(org)
      {:ok, _} = OrgRoles.delete_org_role(role)

      assert {:error, changeset} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)
    end

    test "records who created the key in the product's audit log", %{user: user, product: product} do
      {:ok, _api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "view"})

      assert [log] = AuditLogs.logs_for(product)
      assert log.actor_id == user.id
      assert log.description =~ "created API key CI deploys with the view role"
    end

    test "names a custom role in the audit log", %{user: user, org: org, product: product} do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer"})
      {:ok, _api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      assert [log] = AuditLogs.logs_for(product)
      assert log.description =~ "with the Deployer custom role"
    end
  end

  describe "authenticate/1" do
    test "returns the key with everything its scope needs", %{user: user, org: org, product: product} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})

      assert {:ok, authenticated} = ApiKeys.authenticate(token)
      assert authenticated.id == api_key.id
      assert authenticated.product.id == product.id
      assert authenticated.product.org.id == org.id
      assert ApiKey.assigned_role(authenticated) == :manage
    end

    test "loads a custom role, and comes back with none once it is deleted", %{
      user: user,
      org: org,
      product: product
    } do
      role = Fixtures.org_role_fixture(org, %{name: "Deployer"})
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      assert {:ok, authenticated} = ApiKeys.authenticate(token)
      assert ApiKey.assigned_role(authenticated).id == role.id

      # Only reachable by deleting the role out from under the key, which
      # `delete_org_role/1` refuses while a key holds it.
      {:ok, _} = Repo.update(Ecto.Changeset.change(role, deleted_at: DateTime.utc_now(:second)))
      {:ok, _} = Repo.update(Ecto.Changeset.change(Repo.reload!(api_key), last_used_at: nil))

      assert {:ok, reauthenticated} = ApiKeys.authenticate(token)
      assert is_nil(ApiKey.assigned_role(reauthenticated))
    end

    test "records when the key was last used", %{user: user, product: product} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})
      assert is_nil(api_key.last_used_at)

      {:ok, _} = ApiKeys.authenticate(token)

      assert Repo.reload!(api_key).last_used_at
    end

    test "leaves a recent last used time alone", %{user: user, product: product} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})

      recently = DateTime.add(DateTime.utc_now(:second), -10)
      api_key = Repo.update!(Ecto.Changeset.change(api_key, last_used_at: recently))

      {:ok, _} = ApiKeys.authenticate(token)
      assert Repo.reload!(api_key).last_used_at == recently

      a_while_ago = DateTime.add(DateTime.utc_now(:second), -120)
      api_key = Repo.update!(Ecto.Changeset.change(api_key, last_used_at: a_while_ago))

      {:ok, _} = ApiKeys.authenticate(token)
      assert DateTime.after?(Repo.reload!(api_key).last_used_at, a_while_ago)
    end

    test "refuses a deactivated key", %{user: user, product: product} do
      {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})
      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)

      assert ApiKeys.authenticate(token) == :error
    end

    test "refuses a key for a deleted product", %{user: user, product: product} do
      {:ok, _api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})
      {:ok, _} = Products.delete_product(product)

      assert ApiKeys.authenticate(token) == :error
    end

    test "refuses a key for a deleted org", %{user: user, org: org, product: product} do
      {:ok, _api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})
      {:ok, _} = Accounts.soft_delete_org(org)

      assert ApiKeys.authenticate(token) == :error
    end

    test "refuses anything that isn't a well formed key", %{user: user, product: product} do
      {:ok, _api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})

      # The same length and alphabet, with one character changed, fails the CRC.
      <<prefix::binary-size(5), first, rest::binary>> = token
      altered = <<prefix::binary, if(first == ?a, do: ?b, else: ?a), rest::binary>>

      assert ApiKeys.authenticate(altered) == :error
      assert ApiKeys.authenticate(String.slice(token, 0..-2//1)) == :error
      assert ApiKeys.authenticate("nhpk_" <> String.duplicate("a", 500)) == :error
      assert ApiKeys.authenticate("nhpk_") == :error
      assert ApiKeys.authenticate(Accounts.create_user_api_token(user, "not a key")) == :error
    end
  end

  describe "deactivate/3" do
    test "stops the key and records who did it", %{user: user, product: product} do
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI deploys", "role" => "manage"})

      assert {:ok, deactivated} = ApiKeys.deactivate(product, user, to_string(api_key.id))
      assert deactivated.deactivated_at

      assert [log | _] = AuditLogs.logs_for(product)
      assert log.description =~ "deactivated API key CI deploys"
    end

    test "disconnects any socket still open with the key", %{user: user, product: product} do
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})

      socket_id = ApiKeys.socket_id(api_key)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, socket_id)

      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)

      assert_receive %Broadcast{topic: ^socket_id, event: "disconnect"}
    end

    test "leaves an already deactivated key as it was", %{user: user, product: product} do
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "manage"})
      {:ok, deactivated} = ApiKeys.deactivate(product, user, api_key.id)

      assert {:ok, again} = ApiKeys.deactivate(product, user, api_key.id)
      assert again.deactivated_at == deactivated.deactivated_at
      assert length(AuditLogs.logs_for(product)) == 2
    end

    test "can't reach another product's key", %{user: user, org: org, product: product} do
      other_product = Fixtures.product_fixture(user, org, %{name: "other"})
      {:ok, api_key, _token} = ApiKeys.create(other_product, user, %{"name" => "CI", "role" => "manage"})

      assert ApiKeys.deactivate(product, user, api_key.id) == {:error, :not_found}
      assert ApiKeys.deactivate(product, user, "not-an-id") == {:error, :not_found}
      refute Repo.reload!(api_key).deactivated_at
    end
  end

  describe "list/1" do
    test "lists a product's keys, active ones first", %{user: user, org: org, product: product} do
      {:ok, first, _} = ApiKeys.create(product, user, %{"name" => "first", "role" => "view"})
      {:ok, second, _} = ApiKeys.create(product, user, %{"name" => "second", "role" => "view"})
      {:ok, _} = ApiKeys.deactivate(product, user, first.id)

      other_product = Fixtures.product_fixture(user, org, %{name: "other"})
      {:ok, _, _} = ApiKeys.create(other_product, user, %{"name" => "elsewhere", "role" => "view"})

      assert Enum.map(ApiKeys.list(product), & &1.id) == [second.id, first.id]
    end
  end

  describe "a custom role a key holds" do
    test "can't be deleted while an active key holds it", %{user: user, org: org, product: product} do
      role = Fixtures.org_role_fixture(org)
      {:ok, api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      assert OrgRoles.delete_org_role(role) == {:error, :in_use}

      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)
      assert {:ok, _} = OrgRoles.delete_org_role(role)
    end

    test "doesn't hold a deleted product's keys against it", %{user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "going"})
      role = Fixtures.org_role_fixture(org)
      {:ok, _api_key, _token} = ApiKeys.create(product, user, %{"name" => "CI", "org_role_id" => role.id})

      {:ok, _} = Products.delete_product(product)

      assert {:ok, _} = OrgRoles.delete_org_role(role)
    end
  end
end
