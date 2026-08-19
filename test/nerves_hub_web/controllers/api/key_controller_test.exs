defmodule NervesHubWeb.API.KeyControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Support.EspIdf
  alias NervesHub.Support.Fwup

  describe "index" do
    test "lists all keys", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_key_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index roles" do
    test "error: missing org read", %{conn2: conn, org: org} do
      assert_raise(Ecto.NoResultsError, fn ->
        get(conn, Routes.api_key_path(conn, :index, org.name))
      end)
    end
  end

  describe "create keys" do
    test "renders key when data is valid", %{conn: conn, org: org} do
      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    # Regression: `create` whitelisted only "name" and "key", so a posted
    # `scheme` was silently dropped, defaulted to ed25519, and an RSA PEM was
    # rejected as "not a valid Ed25519 public key". ESP-IDF keys could not be
    # registered through the API at all.
    test "accepts a Secure Boot v2 RSA key", %{conn: conn, org: org} do
      params = %{
        name: "esp release",
        key: EspIdf.signing_public_key(),
        scheme: "secure_boot_v2_rsa"
      }

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), params)

      assert data = json_response(conn, 201)["data"]
      assert data["scheme"] == "secure_boot_v2_rsa"

      {:ok, key} = Accounts.get_org_key_by_name(org, "esp release")
      assert key.scheme == :secure_boot_v2_rsa
    end

    test "defaults to ed25519 when no scheme is given", %{conn: conn, org: org} do
      name = "legacy client"
      Fwup.gen_key_pair(name)

      params = %{name: name, key: Fwup.get_public_key(name)}
      conn = post(conn, Routes.api_key_path(conn, :create, org.name), params)

      assert json_response(conn, 201)["data"]["scheme"] == "ed25519"
    end

    test "rejects an RSA key posted without the matching scheme", %{conn: conn, org: org} do
      params = %{name: "wrong scheme", key: EspIdf.signing_public_key()}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), params)

      assert errors = json_response(conn, 422)["errors"]
      assert Enum.any?(errors["key"] || [], &(&1 =~ "Ed25519"))
    end

    test "invalid keys aren't allowed", %{conn: conn, org: org} do
      key = %{name: "Snoot", key: "Boop", org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)

      assert json_response(conn, 422) == %{
               "errors" => %{"key" => ["invalid key, please check this is a valid Ed25519 public key"]}
             }
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create keys roles" do
    test "ok: org manage", %{conn2: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :manage})

      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org view", %{conn2: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :view})
      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      assert_error_sent(401, fn ->
        post(conn, Routes.api_key_path(conn, :create, org.name), key)
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "delete key" do
    setup([:create_key])

    test "deletes chosen key", %{conn: conn, org: org, key: key} do
      conn = delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))

      assert response(conn, 404)
    end
  end

  describe "delete key roles" do
    setup [:create_key]

    test "ok: org manage", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :manage})
      conn = delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)
    end

    test "error: org view", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :view})

      assert_error_sent(401, fn ->
        delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      end)
      |> assert_authorization_error(401)
    end
  end

  defp create_key(%{user: user, org: org}) do
    key = Fixtures.org_key_fixture(org, user)
    {:ok, %{key: key}}
  end
end
