defmodule NervesHubWeb.Live.NewUI.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Ecto.Query, only: [where: 2]

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} = context do
    Endpoint.subscribe("device:#{device.id}")
    context
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
      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      device_two = Fixtures.device_fixture(org, product, firmware)

      token_two = NervesHub.Accounts.create_user_session_token(user_two)

      conn_two =
        build_conn()
        |> init_test_session(%{"user_token" => token_two})

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
      |> Enum.map_join("", fn w ->
        String.at(w, 0)
        |> String.upcase()
      end)
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
        Fixtures.deployment_group_fixture(mismatched_firmware, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(firmware, %{name: "Beta Deployment"})

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
        Fixtures.deployment_group_fixture(firmware2, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(firmware, %{name: "Beta Deployment"})

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

  describe "sending a manual full update" do
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
      |> assert_has("button[disabled]", text: "Send full update")

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: product.id,
          device_id: device_id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> DeviceConnection.update_changeset(%{
          disconnected_at: DateTime.utc_now(),
          status: :disconnected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device_id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button[disabled]", text: "Send full update")
    end

    test "broadcasts the firmware update request, using the default url config", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      fixture: %{firmware: firmware}
    } do
      assert device.updates_enabled

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: firmware.version, exact_option: false)
      |> click_button("Send full update")

      %{version: version, architecture: architecture, platform: platform} = firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "http://localhost:1234")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "broadcasts the firmware update request, and includes the Orgs `firmware_proxy_url` setting", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      fixture: %{firmware: firmware}
    } do
      Org
      |> where(id: ^org.id)
      |> Repo.update_all(set: [settings: %Org.Settings{firmware_proxy_url: "https://files.customer.com/download"}])

      assert device.updates_enabled

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: firmware.version, exact_option: false)
      |> click_button("Send full update")

      %{version: version, architecture: architecture, platform: platform} = firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "https://files.customer.com/download?firmware=")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "broadcasts the firmware update request using the 'send delta' option", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      firmware_metadata = Map.put(device.firmware_metadata, :fwup_version, "1.13.0")

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_metadata: firmware_metadata, latest_connection_id: latest_connection_id])

      device = Repo.reload(device)

      Firmware
      |> where(id: ^new_firmware.id)
      |> Repo.update_all(set: [delta_updatable: true, version: "2.0.0"])

      new_firmware = Repo.reload(new_firmware)

      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      _ = Fixtures.firmware_delta_fixture(firmware, new_firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: new_firmware.version, exact_option: false)
      |> click_button("Send delta update")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.ends_with?(firmware_url, ".delta.fw")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end
  end

  describe "skip the queue when there is an available update" do
    test "only shows the button if an update is available", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("button", text: "Skip the queue")

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button", text: "Skip the queue")
    end

    test "allows a device to be sent the available update immediately, using the default url config", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "http://localhost:1234")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "allows a device to be sent the available update immediately, using the available Org `firmware_proxy_url` setting",
         %{
           conn: conn,
           org: org,
           org_key: org_key,
           product: product,
           device: device,
           deployment_group: deployment_group,
           tmp_dir: tmp_dir
         } do
      Org
      |> where(id: ^org.id)
      |> Repo.update_all(set: [settings: %Org.Settings{firmware_proxy_url: "https://files.customer.com/download"}])

      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "https://files.customer.com/download?")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "allows a device to be sent the available delta update immediately, if a delta is available", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      metadata = Map.put(device.firmware_metadata, :fwup_version, "1.13.0") |> Map.from_struct()
      Devices.update_device(device, %{firmware_metadata: metadata})

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      Firmware
      |> where(id: ^new_firmware.id)
      |> Repo.update_all(set: [delta_updatable: true, version: "2.0.0"])

      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      _ = Fixtures.firmware_delta_fixture(firmware, new_firmware)

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id, delta_updatable: true])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: "2.0.0",
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.ends_with?(firmware_url, ".delta.fw")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end
  end

  test "does not show the firmware box in the header if the firmware isn't reverted, or validated, or not validated", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> refute_has("span", text: "Firmware:")
  end

  test "shows if a firmware revert is detected", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [firmware_auto_revert_detected: true])

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> assert_has("span", text: "Revert detected")
  end

  test "shows if the firmware has been validated", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [firmware_validation_status: :validated])

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> assert_has("span", text: "Validated")
  end

  test "shows if the firmware has not been validated", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [firmware_validation_status: :not_validated])

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> assert_has("span", text: "Not validated")
  end

  test "does not show if the firmware validation is unknown", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [firmware_validation_status: :unknown])

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> refute_has("span", text: "Firmware:")
  end

  test "updates the firmware validation box when a firmware validation message is received", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [firmware_validation_status: :not_validated])

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "Not validated")

    Devices.firmware_validated(device)

    assert_has(conn, "span", text: "Validated")
  end
end
