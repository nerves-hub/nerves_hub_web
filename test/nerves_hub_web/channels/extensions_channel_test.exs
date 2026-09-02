defmodule NervesHubWeb.ExtensionsChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Consoles
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.NetworkIdentities
  alias NervesHub.Devices.PubSub, as: DevicesPubSub
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHub.Support.Utils
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  alias Phoenix.Socket.Broadcast

  # :analytics_enabled is global, and one test below turns it off. Without
  # restoring it, that setting outlives this file and every later test in the
  # same partition that expects analytics sees it disabled -- which surfaces as
  # a rendering assertion failing somewhere unrelated. Whether it bites at all
  # depends on the seed, so it fails on some runs and not others.
  setup do
    original = Application.get_env(:nerves_hub, :analytics_enabled)

    Application.put_env(:nerves_hub, :analytics_enabled, true)

    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

    :ok
  end

  test "joining device channel works without understanding extensions", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "joining extensions channel works when the device has connected for the first time" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    {:ok, device} =
      Devices.create_device(%{
        product_id: product.id,
        org_id: org.id,
        identifier: Ecto.UUID.generate()
      })

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    # simulate the device channel updating the params
    params = %{
      "nerves_fw_uuid" => Ecto.UUID.generate(),
      "nerves_fw_product" => product.name,
      "nerves_fw_architecture" => "arm64",
      "nerves_fw_version" => "0.0.0",
      "nerves_fw_platform" => "test_host"
    }

    # taken from `DeviceChannel`, I don't love just stealing this, but it will do for now
    with {:ok, metadata} <- Firmwares.metadata_from_device(params, product.id),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata, :unknown, false) do
      FirmwareUpdates.firmware_update_successful(device, device.firmware_metadata)
    end

    assert {:ok, ["health"], extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    push(extensions_channel, "health:attached")
    assert_push("health:check", _)

    :ok = PubSub.subscribe_reports(device.id)

    push(extensions_channel, "health:report", %{"value" => dummy_health_report()})
    assert_receive %Broadcast{event: "health_check_report"}

    assert Repo.aggregate(Devices.DeviceHealth, :count) == 1
  end

  test "a device detaching the local shell it never attached does not take the channel down", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)

    product = Products.get_product!(device.product_id)
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, device} = Devices.enable_extension_setting(device, "local_shell")

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _attach_list, extensions_channel} =
      subscribe_and_join_with_default_device_api_version(
        socket,
        ExtensionsChannel,
        "extensions",
        %{"local_shell" => "0.0.1"}
      )

    ref = Process.monitor(extensions_channel.channel_pid)

    # `Extensions.Dispatch` routes "detached" to `LocalShell.detach/1` on the
    # extension being allowed alone -- it never checks that an "attached" came
    # first, and it does not rescue the call. A device can therefore send these
    # in any order, including a detach for a shell it never attached and a
    # repeat detach after a real one.
    push(extensions_channel, "local_shell:detached")
    push(extensions_channel, "local_shell:attached")
    push(extensions_channel, "local_shell:detached")
    push(extensions_channel, "local_shell:detached")

    refute_receive {:DOWN, ^ref, :process, _, _}, 200
    refute Consoles.PubSub.local_shell_active?(device.id)

    close_cleanly(extensions_channel)
  end

  test "joining extensions channel suggests attaching geo, health, and logging", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, _extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1",
                 "logging" => "0.0.1"
               }
             )

    assert "health" in attach_list
    assert "geo" in attach_list
    assert "logging" in attach_list
  end

  test "a device that batches its log lines is attached too", %{tmp_dir: tmp_dir} do
    # 0.1.0 is how a device says it may put many log lines in one message, and
    # it is served by a different module than the 0.0.1 devices alongside it.
    # A NervesHub that has only the 0.0.1 extension matches `~> 0.0.1` and
    # leaves logging out of the attach list rather than attaching it and
    # dropping every batch it cannot read.
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, _extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"logging" => "0.1.0"}
             )

    assert "logging" in attach_list
  end

  test "joining extensions channel with unknown extensions is fine", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], _extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "goof" => "0.0.1",
                 "health" => "0.0.1"
               }
             )
  end

  test "a new device connecting via Shared Secrets (JITP) and joining extensions channel is fine" do
    Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

    on_exit(fn ->
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    assert {:ok, auth} = Products.create_shared_secret_auth(product)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{x_headers: Utils.nh1_key_secret_headers(auth, Ecto.UUID.generate())})

    params = %{
      "nerves_fw_uuid" => Ecto.UUID.generate(),
      "nerves_fw_product" => product.name,
      "nerves_fw_architecture" => "arm64",
      "nerves_fw_version" => "0.0.0",
      "nerves_fw_platform" => "test_host"
    }

    device = Repo.one(Device)

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, _extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1"
               }
             )

    assert "health" in attach_list
    assert "geo" in attach_list
  end

  test "product with extensions disabled does not suggest attaching anything", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "health")
    Products.disable_extension_setting(product, "geo")
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, [], _} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1"
               }
             )
  end

  test "product with only health suggests only health", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "geo")
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], _} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1"
               }
             )
  end

  test "if platform analytics is disabled, the logging extension isn't attached", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)

    original = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["geo", "health"], _} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1",
                 "logging" => "0.0.1"
               }
             )
  end

  test "attached health extension will receive request for health report", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], socket} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    push(socket, "health:attached")
    assert_push("health:check", _)
  end

  test "a page opening asks the attached health extension for a report", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], socket} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    push(socket, "health:attached")
    assert_push("health:check", _)

    # What the device Show LiveView does on mount. The whole point of the round
    # trip is that the device is asked by the channel, so a second page opening
    # adds nothing to what the device is already being sent.
    :ok = PubSub.watch_health(device.id)

    assert_push("health:check", _)
  end

  test "attached geo extension will receive request for location update", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["geo"], socket} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"geo" => "0.0.1"}
             )

    push(socket, "geo:attached")
    assert_push("geo:location:request", _)
  end

  test "attached extensions will receive detach events on disabling at product level", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, socket} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1"
               }
             )

    assert "health" in attach_list
    assert "geo" in attach_list
    push(socket, "health:attached")
    push(socket, "geo:attached")
    assert_push("geo:location:request", _)
    assert_push("health:check", _)
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "geo")
    assert_push("detach", %{"extensions" => ["geo"]})
    Products.disable_extension_setting(product, "health")
    assert_push("detach", %{"extensions" => ["health"]})
  end

  test "disabled extensions can be re-attached", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, socket} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{
                 "geo" => "0.0.1",
                 "health" => "0.0.1"
               }
             )

    assert "health" in attach_list
    assert "geo" in attach_list
    push(socket, "health:attached")
    push(socket, "geo:attached")
    assert_push("geo:location:request", _)
    assert_push("health:check", _)
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "geo")
    assert_push("detach", %{"extensions" => ["geo"]})
    Products.disable_extension_setting(product, "health")
    assert_push("detach", %{"extensions" => ["health"]})
    Products.enable_extension_setting(product, "geo")
    assert_push("attach", %{"extensions" => ["geo"]})
    Products.enable_extension_setting(product, "health")
    assert_push("attach", %{"extensions" => ["health"]})
  end

  describe "the network identity extension" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, dir: tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      # Opt in at the product level, which is where every extension starts off.
      product = Products.get_product!(device.product_id)
      {:ok, _product} = Products.enable_extension_setting(product, "network_identity")

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      %{device: device, socket: socket, certificate: certificate}
    end

    defp join_extensions(socket) do
      assert {:ok, attach_list, socket} =
               subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
                 "device_api_version" => "2.2.0",
                 "network_identity" => "0.0.1"
               })

      {attach_list, socket}
    end

    test "is offered to a device that supports it", %{socket: socket} do
      {attach_list, _socket} = join_extensions(socket)
      assert "network_identity" in attach_list
    end

    test "asks the device for its identities once on attach", %{socket: socket} do
      {_attach_list, socket} = join_extensions(socket)

      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})
    end

    test "records what the device reports and tells the UI", %{device: device, socket: socket} do
      {_attach_list, socket} = join_extensions(socket)

      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})

      DevicesPubSub.subscribe(device.id)

      push(socket, "network_identity:report", %{
        "identities" => [
          %{
            "service" => "iroh",
            "identifier" => "abc123",
            "details" => %{"ticket" => "a-connection-ticket"}
          }
        ]
      })

      assert_receive %Broadcast{event: "network_identities:updated"}

      assert [identity] = NetworkIdentities.list_for_device(device.id)
      assert identity.service == :iroh
      assert identity.identifier == "abc123"
      assert identity.details == %{"ticket" => "a-connection-ticket"}
    end

    test "records two endpoints of one service separately", %{device: device, socket: socket} do
      # A device running an iroh console and an iroh application reports both.
      # They are both iroh, and neither should overwrite the other.
      {_attach_list, socket} = join_extensions(socket)
      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})

      DevicesPubSub.subscribe(device.id)

      push(socket, "network_identity:report", %{
        "identities" => [
          %{"service" => "iroh", "instance" => "iroh_console", "identifier" => "console-key"},
          %{"service" => "iroh", "instance" => "kiosk_sync", "identifier" => "sync-key"}
        ]
      })

      assert_receive %Broadcast{event: "network_identities:updated"}
      assert_receive %Broadcast{event: "network_identities:updated"}

      assert [%{instance: "iroh_console"}, %{instance: "kiosk_sync"}] =
               NetworkIdentities.list_for_device(device.id)
    end

    test "records several identities from one report", %{device: device, socket: socket} do
      {_attach_list, socket} = join_extensions(socket)
      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})

      DevicesPubSub.subscribe(device.id)

      push(socket, "network_identity:report", %{
        "identities" => [
          %{"service" => "iroh", "identifier" => "iroh-key"},
          %{"service" => "netbird", "identifier" => "netbird-key"}
        ]
      })

      assert_receive %Broadcast{event: "network_identities:updated"}
      assert_receive %Broadcast{event: "network_identities:updated"}

      assert [%{service: :iroh}, %{service: :netbird}] =
               NetworkIdentities.list_for_device(device.id)
    end

    test "a service we don't support doesn't cost the device its other identities", %{device: device, socket: socket} do
      {_attach_list, socket} = join_extensions(socket)
      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})

      DevicesPubSub.subscribe(device.id)

      push(socket, "network_identity:report", %{
        "identities" => [
          %{"service" => "zerotier", "identifier" => "unsupported"},
          %{"service" => "iroh", "identifier" => "still-recorded"}
        ]
      })

      assert_receive %Broadcast{event: "network_identities:updated"}

      assert [%{service: :iroh, identifier: "still-recorded"}] =
               NetworkIdentities.list_for_device(device.id)
    end

    test "a malformed report does not take the connection down", %{device: device, socket: socket} do
      {_attach_list, socket} = join_extensions(socket)
      push(socket, "network_identity:attached")
      assert_push("network_identity:request", %{})

      push(socket, "network_identity:report", %{"identities" => "not-a-list"})
      push(socket, "network_identity:report", %{"identities" => [%{"nonsense" => true}]})

      DevicesPubSub.subscribe(device.id)

      # The channel is still serving this device: a good report after the bad
      # ones still lands.
      push(socket, "network_identity:report", %{
        "identities" => [%{"service" => "iroh", "identifier" => "after-the-garbage"}]
      })

      assert_receive %Broadcast{event: "network_identities:updated"}

      assert [%{identifier: "after-the-garbage"}] = NetworkIdentities.list_for_device(device.id)
    end

    test "is not offered to a device whose product has it switched off", %{device: device, certificate: certificate} do
      product = Products.get_product!(device.product_id)
      {:ok, _product} = Products.disable_extension_setting(product, "network_identity")

      # The allowed set is worked out when the device authenticates, so this
      # needs a fresh connection rather than the one opened during setup.
      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {attach_list, _socket} = join_extensions(socket)

      refute "network_identity" in attach_list
    end
  end

  describe "the error reports extension" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "err-1"}, dir: tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      # Opt in at the product level, which is where every extension starts off.
      product = Products.get_product!(device.product_id)
      {:ok, _product} = Products.enable_extension_setting(product, "error_reports")

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      %{device: device, socket: socket, certificate: certificate}
    end

    defp join_error_reports(socket, version \\ "0.1.0") do
      assert {:ok, attach_list, socket} =
               subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
                 "device_api_version" => "2.2.0",
                 "error_reports" => version
               })

      {attach_list, socket}
    end

    test "is offered to a device that supports it", %{socket: socket} do
      {attach_list, _socket} = join_error_reports(socket)

      assert "error_reports" in attach_list
    end

    # There is no single-report version of this extension, so a device claiming
    # one is a device the platform cannot serve.
    test "a device declaring a version we do not implement gets nothing", %{socket: socket} do
      {attach_list, _socket} = join_error_reports(socket, "0.0.1")

      refute "error_reports" in attach_list
    end

    test "is not offered to a device whose product has it switched off", %{
      device: device,
      certificate: certificate
    } do
      product = Products.get_product!(device.product_id)
      {:ok, _product} = Products.disable_extension_setting(product, "error_reports")

      # The allowed set is worked out when the device authenticates, so this
      # needs a fresh connection rather than the one opened during setup.
      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {attach_list, _socket} = join_error_reports(socket)

      refute "error_reports" in attach_list
    end

    test "is not offered to a device that has it switched off", %{
      device: device,
      certificate: certificate
    } do
      {:ok, _device} = Devices.disable_extension_setting(device, "error_reports")

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {attach_list, _socket} = join_error_reports(socket)

      refute "error_reports" in attach_list
    end
  end

  test "unknown extension event returns detach error reply", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "abc-unknown"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, _attach_list, extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    ref = push(extensions_channel, "unknown_ext:some_event", %{})
    assert_reply(ref, :error, "detach")
  end

  test "message to detached extension is silently ignored", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "abc-detached"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    ref = push(extensions_channel, "health:some_event", %{})
    refute_reply(ref, :ok)
    refute_reply(ref, :error)
  end

  test "extension error event transitions status to detached without crashing", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "abc-error"}, dir: tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _device_channel} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device:#{device.id}")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], extensions_channel} =
             subscribe_and_join_with_default_device_api_version(
               socket,
               ExtensionsChannel,
               "extensions",
               %{"health" => "0.0.1"}
             )

    push(extensions_channel, "health:attached")
    assert_push("health:check", _)

    push(extensions_channel, "health:error", %{})
    assert Process.alive?(extensions_channel.channel_pid)
  end

  def device_fixture(user, device_params \\ %{}, opts) do
    org = Keyword.get(opts, :org) || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, opts[:dir])

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: opts[:dir]
      })

    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {device, firmware, deployment_group}
  end

  def dummy_health_report() do
    %{
      alarms: %{},
      checks: %{},
      metadata: %{},
      timestamp: "2025-01-20T20:00:37.106480Z",
      connectivity: %{}
    }
  end

  defp subscribe_and_join_with_default_device_api_version(socket, channel, topic),
    do: subscribe_and_join(socket, channel, topic, %{"device_api_version" => "2.2.0"})

  defp subscribe_and_join_with_default_device_api_version(socket, channel, topic, payload),
    do: subscribe_and_join(socket, channel, topic, Map.merge(%{"device_api_version" => "2.2.0"}, payload))
end
