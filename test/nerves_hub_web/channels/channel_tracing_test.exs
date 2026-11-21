defmodule NervesHubWeb.ChannelTracingTest do
  # Not async: it swaps the exporter every test's spans go through.
  use NervesHubWeb.ChannelCase

  alias NervesHub.Extensions.Health
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel

  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  setup do
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
  end

  test "a device's channel spans say which device they're about, and what it sent", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.1", dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} = connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", %{"device_api_version" => "2.2.0"})

    {:ok, ["health"], extensions_channel} =
      subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
        "device_api_version" => "2.2.0",
        "health" => "0.0.1"
      })

    push(device_channel, "rebooting", %{})
    push(extensions_channel, "health:attached")
    send(extensions_channel.channel_pid, {Health, :first_check})

    # Each channel has finished with what it was sent once it answers.
    _ = :sys.get_state(device_channel.channel_pid)
    _ = :sys.get_state(extensions_channel.channel_pid)

    # Other tests' spans arrive too, so only this device's count. The decorator
    # puts the channel's pid on every span it opens, which isn't ours to check.
    spans =
      for span(name: name, attributes: attributes) <- exported(),
          attributes = :otel_attributes.map(attributes),
          attributes[:"nerves_hub.device.id"] == device.id,
          into: %{},
          do: {name, Map.delete(attributes, "pid")}

    device_attributes = %{
      "nerves_hub.device.id": device.id,
      "nerves_hub.product.id": product.id,
      "nerves_hub.org.id": org.id
    }

    assert spans["Channels.DeviceChannel.join"] == device_attributes
    assert spans["Channels.ExtensionsChannel.join"] == device_attributes

    assert spans["Channels.DeviceChannel.handle_in"] ==
             Map.put(device_attributes, :"nerves_hub.channel.event", "rebooting")

    assert spans["Channels.ExtensionsChannel.handle_in"] ==
             Map.put(device_attributes, :"nerves_hub.channel.event", "health:attached")

    assert spans["Channels.ExtensionsChannel.handle_info[extension]"] ==
             Map.put(device_attributes, :"nerves_hub.extension", "NervesHub.Extensions.Health")
  end

  defp exported() do
    :otel_tracer_provider.force_flush()
    collect_exported([])
  end

  defp collect_exported(spans) do
    receive do
      {:span, span} -> collect_exported([span | spans])
    after
      200 -> spans
    end
  end
end
