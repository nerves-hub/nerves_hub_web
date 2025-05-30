defmodule NervesHubWeb.Live.NewUI.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Ecto.Query, only: [where: 2]

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  alias NervesHubWeb.Endpoint

  setup %{conn: conn, fixture: %{device: device}} = context do
    Endpoint.subscribe("device:#{device.id}")
    conn = init_test_session(conn, %{"new_ui" => true})

    Map.put(context, :conn, conn)
  end

  describe "who is currently viewing the device page" do
    setup %{fixture: %{org: org}} do
      # https://hexdocs.pm/phoenix/Phoenix.Presence.html#module-testing-with-presence
      on_exit(fn ->
        for pid <- NervesHubWeb.Presence.fetchers_pids() do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, _, _, _}, 1000
        end
      end)

      user_two = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, user_two, %{role: :view})

      {:ok, %{user_two: user_two}}
    end

    test "only the current user", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    test "two users, same device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      token_two = NervesHub.Accounts.create_user_session_token(user_two)

      conn_two =
        build_conn()
        |> init_test_session(%{"user_token" => token_two})
        |> init_test_session(%{"new_ui" => true})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
    end

    test "two users, different devices", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      firmware = Firmwares.get_firmware_by_uuid(device.firmware_metadata.uuid)
      device_two = Fixtures.device_fixture(org, product, firmware)

      token_two = NervesHub.Accounts.create_user_session_token(user_two)

      conn_two =
        build_conn()
        |> init_test_session(%{"user_token" => token_two})
        |> init_test_session(%{"new_ui" => true})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device_two.identifier}")
      |> assert_has("h1", text: device_two.identifier)
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
      |> refute_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    defp user_initials(user) do
      String.split(user.name)
      |> Enum.map(fn w ->
        String.at(w, 0)
        |> String.upcase()
      end)
      |> Enum.join("")
    end
  end

  describe "device's deployment group" do
    test "eligible deployment groups are listed when device is provisioned", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      deployment_group: deployment_group,
      fixture: %{firmware: firmware}
    } do
      _ = Devices.set_as_provisioned!(device)
      org_key2 = Fixtures.org_key_fixture(org, user)

      mismatched_firmware =
        Fixtures.firmware_fixture(org_key2, product, %{platform: "Vulture", architecture: "arm"})

      mismatched_firmware_deployment_group =
        Fixtures.deployment_group_fixture(org, mismatched_firmware, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(org, firmware, %{name: "Beta Deployment"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: deployment_group.name)
      |> assert_has("option", text: deployment_group2.name)
      |> refute_has("option", text: mismatched_firmware_deployment_group.name)
    end

    test "product's deployment groups are listed when device is registered", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      deployment_group: deployment_group,
      fixture: %{firmware: firmware}
    } do
      assert device.status == :registered
      org_key2 = Fixtures.org_key_fixture(org, user)
      product2 = Fixtures.product_fixture(user, org, %{name: "Product 123"})
      firmware2 = Fixtures.firmware_fixture(org_key2, product2)

      deployment_group_from_product2 =
        Fixtures.deployment_group_fixture(org, firmware2, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(org, firmware, %{name: "Beta Deployment"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: deployment_group.name)
      |> assert_has("option", text: deployment_group2.name)
      |> refute_has("option", text: deployment_group_from_product2.name)
    end

    test "set deployment group", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Deployment Group", option: deployment_group.name, exact_option: false)
      |> within("#set-deployment-group-form", fn session ->
        submit(session)
      end)
      |> then(fn _ ->
        assert Repo.reload(device) |> Map.get(:deployment_id)
      end)
    end

    test "remove from deployment group", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      device = Devices.update_deployment_group(device, deployment_group)
      assert device.deployment_id

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "Assigned deployment group")
      |> click_button("button[phx-click='remove-from-deployment-group']", "")
      |> then(fn _ ->
        refute Repo.reload(device) |> Map.get(:deployment_id)
      end)
    end
  end

  describe "sending a manual update" do
    test "lists only eligible firmwares for device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      fixture: %{firmware: firmware}
    } do
      mismatched_architecture_firmware =
        Fixtures.org_key_fixture(org, user)
        |> Fixtures.firmware_fixture(product, %{architecture: "arm", version: "1.5.0"})

      mismatched_platform_firmware =
        Fixtures.org_key_fixture(org, user)
        |> Fixtures.firmware_fixture(product, %{platform: "Vulture", version: "1.6.0"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: firmware.version, exact_option: false)
      |> refute_has("option", text: mismatched_architecture_firmware.version, exact_option: false)
      |> refute_has("option", text: mismatched_platform_firmware.version, exact_option: false)
    end

    test "cannot send when device is disconnected", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      device = %{id: device_id} = Repo.preload(device, :latest_connection)
      refute device.latest_connection

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button[disabled]", text: "Send update")

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: product.id,
          device_id: device_id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :disconnected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device_id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button[disabled]", text: "Send update")
    end

    test "updates devices's firmware", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      fixture: %{firmware: firmware}
    } do
      assert device.updates_enabled

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> within("#push-update-form", fn session ->
        session
        |> select("Firmware", option: firmware.version, exact_option: false)
        |> submit()
      end)

      %{version: version, architecture: architecture, platform: platform} = firmware

      assert_receive %Phoenix.Socket.Broadcast{
        payload: %{
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "devices/update-manual"
      }

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end
  end

  test "enabling and disabling priority updates", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    refute device.priority_updates

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> within("#toggle-priority-updates", fn session ->
      session
      |> check("Priority Updates")
    end)

    assert Repo.reload(device) |> Map.get(:priority_updates)
  end
end
