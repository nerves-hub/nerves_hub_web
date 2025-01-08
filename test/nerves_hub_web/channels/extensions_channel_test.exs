defmodule NervesHubWeb.ExtensionsChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel

  test "joining device channel works without understanding extensions" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

    assert_push("extensions:get", _extensions)
  end

  test "joining extensions channel suggests attaching geo and health" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

    assert_push("extensions:get", _extensions)

    assert {:ok, attach_list, _} =
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

  test "joining extensions channel with unknown extensions is fine" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

    assert_push("extensions:get", _extensions)

    assert {:ok, ["health"], _} =
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

  test "product with extensions disabled does not suggest attaching anything" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "health")
    Products.disable_extension_setting(product, "geo")
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  test "product with only health suggests only health" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    product = Products.get_product!(device.product_id)
    Products.disable_extension_setting(product, "geo")
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  test "attached health extension will receive request for health report" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  test "attached geo extension will receive request for location update" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  test "attached extensions will receive detach events on disabling at product level" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  test "disabled extensions can be re-attached" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} =
      subscribe_and_join_with_default_device_api_version(socket, DeviceChannel, "device")

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

  def device_fixture(user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment = Fixtures.deployment_fixture(org, firmware)

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {device, firmware, deployment}
  end

  defp subscribe_and_join_with_default_device_api_version(socket, channel, topic),
    do: subscribe_and_join(socket, channel, topic, %{"device_api_version" => "2.2.0"})

  defp subscribe_and_join_with_default_device_api_version(socket, channel, topic, payload),
    do:
      subscribe_and_join(
        socket,
        channel,
        topic,
        Map.merge(%{"device_api_version" => "2.2.0"}, payload)
      )
end
