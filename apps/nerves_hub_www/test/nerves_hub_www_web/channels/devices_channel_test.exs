defmodule NervesHubWWWWeb.DevicesChannelTest do
  use NervesHubWWWWeb.ChannelCase

  alias NervesHubWebCore.{
    Deployments,
    Devices,
    Devices.Device,
    Firmwares.Firmware,
    Fixtures,
    Repo
  }

  setup do
    {:ok, fixture: Fixtures.very_fixture()}
  end

  describe "can see" do
    test "in-org devices in initial state", %{fixture: fixture} do
      %{device_id: device_id} = connect_device(fixture)
      connect_www(fixture)
      assert_push("presence_state", %{^device_id => %{metas: [%{}], status: "online"}})
    end

    test "in-org devices as they join (online)", %{fixture: fixture} do
      connect_www(fixture)
      %{device_id: device_id} = connect_device(fixture)
      assert_push("presence_state", %{})

      assert_broadcast(
        "presence_diff",
        %{joins: %{^device_id => %{metas: [%{}], status: "online"}}, leaves: %{}}
      )
    end

    test "in-org devices as they join (update pending)", %{fixture: fixture} do
      connect_www(fixture)
      release_deployment(fixture)
      %{device_id: device_id} = connect_device(fixture)
      assert_push("presence_state", %{})

      assert_broadcast(
        "presence_diff",
        %{joins: %{^device_id => %{metas: [%{}], status: "update pending"}}, leaves: %{}}
      )
    end

    test "in-org device leaving", %{fixture: fixture} do
      %{device_id: device_id, socket: device_socket} = connect_device(fixture)
      connect_www(fixture)
      assert_push("presence_state", %{^device_id => %{metas: [%{}], status: "online"}})
      leave(device_socket)

      assert_broadcast(
        "presence_diff",
        %{joins: %{}, leaves: %{^device_id => %{metas: [%{}], status: "online"}}}
      )
    end
  end

  describe "cannot see" do
    setup do
      fixture_2 = Fixtures.smartrent_fixture()
      {:ok, fixture_2: fixture_2}
    end

    test "out-of-org devices in initial state", %{fixture: fixture, fixture_2: fixture_2} do
      %{device_id: device_id} = connect_device(fixture_2)
      connect_www(fixture)
      refute_push("presence_state", %{^device_id => %{metas: [%{}], status: "online"}})
    end

    test "out-of-org devices as they join", %{fixture: fixture, fixture_2: fixture_2} do
      connect_www(fixture)
      %{device_id: device_id} = connect_device(fixture_2)
      assert_push("presence_state", %{})
      refute_broadcast("presence_diff", %{joins: %{^device_id => _}, leaves: %{}})
    end
  end

  describe "terminate" do
    test "saves last_communication", %{fixture: fixture} do
      %{device_id: id, socket: socket} = connect_device(fixture)

      # Set to nil so we change check it gets set on disconnect
      {:ok, device} = Devices.update_device(fixture.device, %{last_communication: nil})
      assert device.last_communication == nil

      leave(socket)
      disconnected_device = Repo.get(Device, id)

      assert disconnected_device.last_communication != nil
    end
  end

  defp connect_device(%{
         device: %Device{id: device_id},
         firmware: %Firmware{uuid: firmware_uuid},
         device_certificate: device_certificate
       }) do
    {:ok, _, socket} =
      NervesHubDeviceWeb.UserSocket
      |> socket("device_socket:#{device_id}", %{
        certificate: device_certificate
      })
      |> Map.put(:endpoint, NervesHubDeviceWeb.Endpoint)
      |> subscribe_and_join(NervesHubDeviceWeb.DeviceChannel, "firmware:#{firmware_uuid}")

    Process.unlink(socket.channel_pid)
    %{device_id: to_string(device_id), socket: socket}
  end

  defp connect_www(%{user: %{id: user_id}, device: %{org_id: org_id}}) do
    socket =
      NervesHubWWWWeb.UserSocket
      |> socket("user_socket:#{user_id}", %{auth_user_id: user_id})
      |> subscribe_and_join!(NervesHubWWWWeb.DevicesChannel, "devices:#{org_id}")

    %{socket: socket}
  end

  defp release_deployment(%{device: device}) do
    %Device{firmware_metadata: %{product: product_name}, org: org} =
      NervesHubWebCore.Repo.preload(device, [:org])

    {:ok, product} =
      NervesHubWebCore.Products.get_product_by_org_id_and_name(org.id, product_name)

    uuid = Ecto.UUID.generate()

    org
    |> Fixtures.org_key_fixture()
    |> Fixtures.firmware_fixture(product, %{
      uuid: uuid,
      version: "0.0.2",
      upload_metadata: %{"public_path" => "http://foo.com/bar"}
    })
    |> Fixtures.deployment_fixture(%{
      name: "a different name",
      conditions: %{
        "version" => ">=0.0.1",
        "tags" => ["beta", "beta-edge"]
      }
    })
    |> Deployments.update_deployment(%{is_active: true})
  end
end
