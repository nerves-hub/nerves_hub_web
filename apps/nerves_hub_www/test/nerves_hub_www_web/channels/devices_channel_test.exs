defmodule NervesHubWWWWeb.DevicesChannelTest do
  use NervesHubWWWWeb.ChannelCase
  alias NervesHubCore.{Deployments, Devices.Device, Firmwares.Firmware, Fixtures}

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
    setup %{fixture: %{user: %{orgs: [%{id: org_id}]}}} do
      %{org: %{id: org_id_2}} = fixture_2 = Fixtures.smartrent_fixture()
      assert org_id != org_id_2
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

  defp connect_www(%{user: %{id: user_id, orgs: [%{id: org_id} | _]}}) do
    socket =
      NervesHubWWWWeb.UserSocket
      |> socket("user_socket:#{user_id}", %{auth_user_id: user_id})
      |> subscribe_and_join!(NervesHubWWWWeb.DevicesChannel, "devices:#{org_id}")

    %{socket: socket}
  end

  defp release_deployment(%{
         device: device
       }) do
    %Device{last_known_firmware: %{product: product}, org: org} =
      NervesHubCore.Repo.preload(device, [:org, last_known_firmware: [:product]])

    uuid = Ecto.UUID.generate()

    org
    |> Fixtures.org_key_fixture(%{name: "another key"})
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
