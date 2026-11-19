defmodule NervesHubWeb.API.ApiKeyAuthenticationTest do
  @moduledoc """
  Product API keys used through the router: which routes a key reaches, how its
  role and its product limit it, and what it leaves in the audit log.
  """

  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Repo

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    %{org_key: org_key, firmware: firmware, device: device}
  end

  defp key_conn(product, user, attrs \\ %{"role" => "manage"}) do
    {:ok, api_key, token} = ApiKeys.create(product, user, Map.put_new(attrs, "name", "CI"))
    {build_auth_conn(token), api_key}
  end

  describe "a manage key" do
    test "works on its product's routes", %{user: user, org: org, product: product, device: device} do
      {conn, _api_key} = key_conn(product, user)

      assert json_response(get(conn, Routes.api_product_path(conn, :show, org.name, product.name)), 200)
      assert [_] = json_response(get(conn, Routes.api_device_path(conn, :index, org.name, product.name)), 200)["data"]
      assert json_response(get(conn, Routes.api_firmware_path(conn, :index, org.name, product.name)), 200)

      assert json_response(
               get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)),
               200
             )

      assert json_response(get(conn, Routes.api_device_path(conn, :show, device.identifier)), 200)
    end

    test "is recorded in the audit log for what it does", %{user: user, org: org, product: product, device: device} do
      {conn, api_key} = key_conn(product, user)

      conn = post(conn, Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier))
      assert response(conn, 204)

      assert [log] = AuditLogs.logs_by(api_key)
      assert log.description == "API key CI rebooted device #{device.identifier}"
    end

    test "is recorded on a release it publishes", %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      firmware: firmware,
      tmp_dir: tmp_dir
    } do
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})
      {conn, api_key} = key_conn(product, user)

      path = Routes.api_deployment_group_path(conn, :update, org.name, product.name, deployment_group.name)
      conn = put(conn, path, deployment: %{"firmware" => new_firmware.uuid})

      assert json_response(conn, 200)["data"]["firmware_uuid"] == new_firmware.uuid

      assert [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)
      assert release.created_by_api_key_id == api_key.id
      assert is_nil(release.created_by_id)
    end

    test "records when it was last used", %{user: user, org: org, product: product} do
      {conn, api_key} = key_conn(product, user)

      assert json_response(get(conn, Routes.api_device_path(conn, :index, org.name, product.name)), 200)

      assert Repo.reload!(api_key).last_used_at
    end

    test "can't move a device to another product", %{user: user, org: org, product: product, device: device} do
      other_product = Fixtures.product_fixture(user, org, %{name: "other"})
      {conn, _api_key} = key_conn(product, user)

      assert_error_sent(401, fn ->
        post(conn, Routes.api_device_path(conn, :move, org.name, product.name, device.identifier), %{
          "new_org_name" => org.name,
          "new_product_name" => other_product.name
        })
      end)
      |> assert_authorization_error()

      assert Repo.reload!(device).product_id == product.id
    end
  end

  describe "a view key" do
    test "can read but not change anything", %{user: user, org: org, product: product, device: device} do
      {conn, api_key} = key_conn(product, user, %{"role" => "view"})

      assert json_response(
               get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)),
               200
             )

      assert_error_sent(401, fn ->
        post(conn, Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier))
      end)
      |> assert_authorization_error()

      assert AuditLogs.logs_by(api_key) == []
    end
  end

  describe "a key with a custom role" do
    test "may do what the role allows, and no more", %{user: user, org: org, product: product, device: device} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter", permissions: ["device:reboot"]})
      {conn, _api_key} = key_conn(product, user, %{"org_role_id" => role.id})

      assert response(post(conn, Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)), 204)

      # Reading is every member's, so the device still shows.
      assert json_response(
               get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)),
               200
             )

      # Nothing granted the role deployment group changes.
      assert_error_sent(401, fn ->
        post(conn, Routes.api_deployment_group_path(conn, :create, org.name, product.name), %{})
      end)
      |> assert_authorization_error()
    end

    test "sees only the devices its tags match", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      device: device
    } do
      tagged = Fixtures.device_fixture(org, product, firmware, %{identifier: "tagged", tags: ["canary"]})

      role = Fixtures.org_role_fixture(org, %{name: "Canary only", device_tags: ["canary"]})
      {conn, _api_key} = key_conn(product, user, %{"org_role_id" => role.id})

      identifiers =
        conn
        |> get(Routes.api_device_path(conn, :index, org.name, product.name))
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["identifier"])

      assert identifiers == [tagged.identifier]

      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier))
      end)
      |> assert_authorization_error(404)
    end

    test "grants nothing once the role is deleted", %{user: user, org: org, product: product, device: device} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter", permissions: ["device:reboot"]})
      {conn, _api_key} = key_conn(product, user, %{"org_role_id" => role.id})

      # Only reachable by deleting the role out from under the key, which
      # `delete_org_role/1` refuses while a key holds it.
      {:ok, _} = Repo.update(Ecto.Changeset.change(role, deleted_at: DateTime.utc_now(:second)))

      assert_error_sent(404, fn ->
        post(conn, Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier))
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "a key is kept to its own product" do
    test "another product in the same org is not found", %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      sibling = Fixtures.product_fixture(user, org, %{name: "sibling"})
      sibling_firmware = Fixtures.firmware_fixture(org_key, sibling, %{dir: tmp_dir})
      sibling_device = Fixtures.device_fixture(org, sibling, sibling_firmware)

      # The person who made the key can reach the sibling product. The key can't.
      {conn, _api_key} = key_conn(product, user)

      for path <- [
            Routes.api_product_path(conn, :show, org.name, sibling.name),
            Routes.api_device_path(conn, :index, org.name, sibling.name),
            Routes.api_device_path(conn, :show, org.name, sibling.name, sibling_device.identifier),
            Routes.api_device_path(conn, :show, org.name, product.name, sibling_device.identifier),
            Routes.api_device_path(conn, :show, sibling_device.identifier)
          ] do
        assert_error_sent(404, fn -> get(conn, path) end)
        |> assert_authorization_error(404)
      end
    end

    test "a URL naming another org is not found, even with the same product name", %{
      user: user,
      product: product
    } do
      other_org = Fixtures.org_fixture(user, %{name: "other-org"})
      _same_name = Fixtures.product_fixture(user, other_org, %{name: product.name})
      {conn, _api_key} = key_conn(product, user)

      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :index, other_org.name, product.name))
      end)
      |> assert_authorization_error(404)
    end

    test "a device certificate from another product isn't recognized", %{
      user: user,
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      sibling = Fixtures.product_fixture(user, org, %{name: "sibling"})
      sibling_firmware = Fixtures.firmware_fixture(org_key, sibling, %{dir: tmp_dir})
      sibling_device = Fixtures.device_fixture(org, sibling, sibling_firmware)
      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{sibling_device.identifier}", ca, ca_key)

      _device_certificate = Fixtures.device_certificate_fixture(sibling_device, cert)
      cert64 = cert |> X509.Certificate.to_pem() |> Base.encode64()

      {conn, _api_key} = key_conn(product, user)
      conn = post(conn, Routes.api_device_path(conn, :auth, org.name, product.name), %{"certificate" => cert64})

      assert response(conn, 403)
    end
  end

  describe "a key can't reach" do
    test "routes about users or organizations", %{user: user, org: org, product: product} do
      {conn, _api_key} = key_conn(product, user)

      for path <- [
            Routes.api_user_path(conn, :me),
            Routes.api_org_path(conn, :index),
            Routes.api_org_user_path(conn, :index, org.name),
            Routes.api_key_path(conn, :index, org.name),
            Routes.api_product_path(conn, :index, org.name)
          ] do
        assert_error_sent(401, fn -> get(conn, path) end)
        |> assert_authorization_error()
      end
    end

    test "changing or deleting the product itself", %{user: user, org: org, product: product} do
      {conn, _api_key} = key_conn(product, user)
      path = Routes.api_product_path(conn, :update, org.name, product.name)

      # Reading the product is fine; changing or deleting it is left to people.
      assert json_response(get(conn, Routes.api_product_path(conn, :show, org.name, product.name)), 200)

      assert_error_sent(401, fn -> put(conn, path, %{"allow_unsigned_atomvm_firmware" => true}) end)
      |> assert_authorization_error()

      assert_error_sent(401, fn -> delete(conn, path) end)
      |> assert_authorization_error()

      reloaded = Repo.reload!(product)
      refute reloaded.allow_unsigned_atomvm_firmware
      refute reloaded.deleted_at
    end
  end

  describe "a key stops working" do
    test "once it is deactivated", %{user: user, org: org, product: product} do
      {conn, api_key} = key_conn(product, user)
      {:ok, _} = ApiKeys.deactivate(product, user, api_key.id)

      assert_error_sent(401, fn ->
        get(conn, Routes.api_device_path(conn, :index, org.name, product.name))
      end)
      |> assert_authorization_error()
    end

    test "once its product is deleted", %{user: user, org: org, product: product} do
      {conn, _api_key} = key_conn(product, user)
      Repo.update!(Ecto.Changeset.change(product, deleted_at: DateTime.utc_now(:second)))

      assert_error_sent(401, fn ->
        get(conn, Routes.api_device_path(conn, :index, org.name, product.name))
      end)
      |> assert_authorization_error()
    end
  end
end
