defmodule NervesHubWeb.API.DeviceSharedSecretControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias Phoenix.Socket.Broadcast

  setup %{org: org, product: product} do
    {:ok, device} =
      Devices.create_device(%{identifier: "device-1234", org_id: org.id, product_id: product.id})

    [device: device]
  end

  defp secrets_path(org, product, device),
    do: ~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}/shared_secrets"

  # ~p encodes the key as a path segment, which matters for keys made before
  # keys were URL-safe.
  defp secrets_path(org, product, device, key),
    do: ~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}/shared_secrets/#{key}"

  describe "create" do
    test "returns a new key and secret the device can connect with, and audits it", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      data = conn |> post(secrets_path(org, product, device)) |> json_response(201) |> Map.fetch!("data")

      assert "nhd_" <> _ = data["key"]
      assert is_binary(data["secret"])
      assert data["deactivated_at"] == nil

      assert {:ok, auth} = Devices.get_shared_secret_auth(data["key"])
      assert auth.device_id == device.id
      assert auth.secret == data["secret"]

      assert [%{actor_id: actor_id}] = AuditLogs.logs_for(device)
      assert actor_id == user.id
    end

    test "gives each request a different key and secret", %{conn: conn, org: org, product: product, device: device} do
      first = conn |> post(secrets_path(org, product, device)) |> json_response(201) |> Map.fetch!("data")
      second = conn |> post(secrets_path(org, product, device)) |> json_response(201) |> Map.fetch!("data")

      assert first["key"] != second["key"]
      assert first["secret"] != second["secret"]
      assert length(Devices.list_shared_secret_auths(device)) == 2
    end

    test "is refused for a deleted device", %{conn: conn, org: org, product: product, device: device} do
      {:ok, device} = Devices.update_device(device, %{deleted_at: DateTime.utc_now()})

      assert conn |> post(secrets_path(org, product, device)) |> json_response(422) ==
               %{"errors" => %{"detail" => "Device is deleted and must be restored to use."}}

      assert Devices.list_shared_secret_auths(device) == []
    end

    test "needs the manage role", %{conn2: conn2, org: org, product: product, device: device, user2: user2} do
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn -> post(conn2, secrets_path(org, product, device)) end)
      |> assert_authorization_error(401)

      assert Devices.list_shared_secret_auths(device) == []
    end
  end

  describe "index" do
    test "lists the device's keys, deactivated ones included, without their secrets", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, active} = Devices.create_shared_secret_auth(device)
      {:ok, deactivated} = Devices.create_shared_secret_auth(device)
      {:ok, _} = Devices.deactivate_shared_secret_auth(device, deactivated.key, user)

      data = conn |> get(secrets_path(org, product, device)) |> json_response(200) |> Map.fetch!("data")

      assert Enum.map(data, & &1["key"]) == [active.key, deactivated.key]
      refute Enum.any?(data, &Map.has_key?(&1, "id"))
      assert [%{"deactivated_at" => nil}, %{"deactivated_at" => deactivated_at}] = data
      assert is_binary(deactivated_at)
      refute Enum.any?(data, &Map.has_key?(&1, "secret"))
    end

    test "is open to view-only members", %{conn2: conn2, org: org, product: product, device: device, user2: user2} do
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})
      {:ok, auth} = Devices.create_shared_secret_auth(device)

      assert [listed] = conn2 |> get(secrets_path(org, product, device)) |> json_response(200) |> Map.fetch!("data")
      assert listed["key"] == auth.key
      refute Map.has_key?(listed, "secret")
    end
  end

  describe "delete" do
    test "deactivates the key, disconnects the device, and audits it", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{device.id}")

      assert conn |> delete(secrets_path(org, product, device, auth.key)) |> response(204)

      assert {:error, :not_found} = Devices.get_shared_secret_auth(auth.key)
      assert %{deactivated_at: %DateTime{}} = NervesHub.Repo.get!(Devices.SharedSecretAuth, auth.id)
      assert_receive %Broadcast{event: "disconnect"}
      assert [%{actor_id: actor_id}] = AuditLogs.logs_for(device)
      assert actor_id == user.id
    end

    test "returns not found for an already deactivated key", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      {:ok, deactivated} = Devices.deactivate_shared_secret_auth(device, auth.key, user)

      assert conn |> delete(secrets_path(org, product, device, auth.key)) |> json_response(404)

      assert NervesHub.Repo.get!(Devices.SharedSecretAuth, auth.id).deactivated_at == deactivated.deactivated_at
    end

    test ~s(handles a key made before keys were URL-safe, with "/" and "+"), %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      key = "nhd_a/b+c" <> String.duplicate("d", 38)
      {:ok, auth} = auth |> Ecto.Changeset.change(key: key) |> NervesHub.Repo.update()

      assert {:ok, _} = Devices.get_shared_secret_auth(key)

      assert conn |> delete(secrets_path(org, product, device, auth.key)) |> response(204)
      assert {:error, :not_found} = Devices.get_shared_secret_auth(key)
    end

    test "is refused for a deleted device", %{conn: conn, org: org, product: product, device: device} do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      {:ok, device} = Devices.update_device(device, %{deleted_at: DateTime.utc_now()})

      assert conn |> delete(secrets_path(org, product, device, auth.key)) |> json_response(422) ==
               %{"errors" => %{"detail" => "Device is deleted and must be restored to use."}}
    end

    test "only reaches the device's own keys", %{conn: conn, org: org, product: product, device: device} do
      {:ok, other_device} =
        Devices.create_device(%{identifier: "device-5678", org_id: org.id, product_id: product.id})

      {:ok, other_auth} = Devices.create_shared_secret_auth(other_device)

      assert conn |> delete(secrets_path(org, product, device, other_auth.key)) |> json_response(404)

      assert {:ok, _} = Devices.get_shared_secret_auth(other_auth.key)
    end

    test "returns not found for an unknown key", %{conn: conn, org: org, product: product, device: device} do
      assert conn |> delete(secrets_path(org, product, device, "nhd_unknown")) |> json_response(404)
    end

    test "needs the manage role", %{conn2: conn2, org: org, product: product, device: device, user2: user2} do
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})
      {:ok, auth} = Devices.create_shared_secret_auth(device)

      assert_error_sent(401, fn -> delete(conn2, secrets_path(org, product, device, auth.key)) end)
      |> assert_authorization_error(401)

      assert {:ok, _} = Devices.get_shared_secret_auth(auth.key)
    end
  end
end
