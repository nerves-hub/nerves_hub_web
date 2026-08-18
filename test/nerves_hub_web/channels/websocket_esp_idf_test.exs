defmodule NervesHubWeb.WebsocketEspIdfTest do
  @moduledoc """
  End-to-end cover for an ESP-IDF device on the device socket.

  Every join payload here is the JSON `nerves-hub-link-esp32` actually sends —
  see `FirmwareMetadata::join_params` in that crate, and the assertions in its
  `metadata::tests`. The two sides are checked independently: the crate's unit
  tests assert it produces these keys, and this asserts the server does the
  right thing when it receives them. Change one and this should fail.
  """
  use NervesHubWeb.ChannelCase

  import Ecto.Query
  import TrackerHelper

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Support.EspIdf
  alias NervesHubWeb.DeviceEndpoint

  @device_port Application.compile_env(:nerves_hub, DeviceEndpoint) |> get_in([:https, :port])
  @valid_serial "device-1234"

  @socket_config [
    uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
    json_parser: Jason,
    reconnect_after_msec: [500],
    rejoin_after_msec: [500],
    mint_opts: [
      protocols: [:http1],
      transport_opts: [
        verify: :verify_peer,
        versions: [:"tlsv1.2"],
        certfile: Path.expand("test/fixtures/ssl/device-1234-cert.pem") |> to_charlist(),
        keyfile: Path.expand("test/fixtures/ssl/device-1234-key.pem") |> to_charlist(),
        cacertfile: Path.expand("test/fixtures/ssl/ca.pem") |> to_charlist(),
        server_name_indication: ~c"device.nerves-hub.org"
      ]
    ]
  ]

  # Exactly what nerves-hub-link-esp32 sends on phx_join.
  defp esp_join_params(elf_sha256, overrides \\ %{}) do
    Map.merge(
      %{
        "device_api_version" => "2.2.0",
        "update_tool" => "esp-idf",
        "esp_idf_project_name" => "my_app",
        "esp_idf_version" => "1.0.0",
        "esp_idf_app_elf_sha256" => Base.encode16(elf_sha256, case: :lower),
        "esp_idf_ver" => "v5.2.1",
        "esp_idf_chip_id" => 9
      },
      overrides
    )
  end

  setup context do
    Process.put(:websocket_serializer, :json)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "my_app"})

    # A real ESP-IDF image, uploaded the same way a user would.
    elf_sha256 = :crypto.strong_rand_bytes(32)

    {:ok, path} =
      EspIdf.create_firmware(product.name,
        dir: context[:tmp_dir] || System.tmp_dir!(),
        version: "1.0.0",
        elf_sha256: elf_sha256
      )

    {:ok, firmware} = Firmwares.create_firmware(org, path)

    device =
      Fixtures.device_fixture(org, product, firmware, %{identifier: @valid_serial})

    _ = Fixtures.device_certificate_fixture(device)

    {:ok,
     %{
       user: user,
       org: org,
       product: product,
       firmware: firmware,
       device: device,
       elf_sha256: elf_sha256
     }}
  end

  describe "an ESP-IDF device joining" do
    @describetag :tmp_dir

    test "is recorded with metadata derived from esp_app_desc_t", %{
      device: device,
      firmware: firmware,
      elf_sha256: elf_sha256
    } do
      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket, esp_join_params(elf_sha256))

      assert_online_and_available(device)

      device = Devices.get_device(device.id)

      # The device sent no UUID — the server derived it from app_elf_sha256,
      # and it must land on the firmware that was uploaded.
      assert device.firmware_metadata.uuid == firmware.uuid
      assert device.firmware_metadata.product == "my_app"
      assert device.firmware_metadata.version == "1.0.0"
      assert device.firmware_metadata.platform == "esp32s3"
      assert device.firmware_metadata.architecture == "xtensa"

      SocketClient.clean_close(socket)
    end

    test "reconnecting does not record a firmware update every time", %{
      device: device,
      elf_sha256: elf_sha256
    } do
      params = esp_join_params(elf_sha256)

      for _ <- 1..3 do
        {:ok, socket} = SocketClient.start_link(@socket_config)
        SocketClient.join_and_wait(socket, params)
        SocketClient.clean_close(socket)
        eventually(assert(Repo.all(where(DeviceConnection, status: :connected)) == []))
      end

      # An ESP-IDF device never sends `nerves_fw_uuid`, so the "same firmware"
      # fast path used to miss entirely and every join looked like a completed
      # update.
      updates =
        AuditLog
        |> where([a], a.resource_id == ^device.id)
        |> Repo.all()
        |> Enum.filter(&(&1.description =~ "firmware"))

      assert Enum.count(updates) <= 1,
             "expected at most one firmware-update audit entry, got #{Enum.count(updates)}: " <>
               inspect(Enum.map(updates, & &1.description))
    end

    test "accepts update_progress, the tool-neutral progress event", %{
      device: device,
      org: org,
      product: product,
      elf_sha256: elf_sha256,
      tmp_dir: tmp_dir
    } do
      # The inflight update has to target a *different* firmware than the one
      # the device reports running, or the join correctly concludes the update
      # already landed and clears it.
      {:ok, path} =
        EspIdf.create_firmware(product.name,
          dir: tmp_dir,
          version: "1.1.0",
          elf_sha256: :crypto.strong_rand_bytes(32)
        )

      {:ok, target} = Firmwares.create_firmware(org, path)
      {:ok, inflight_update} = Fixtures.inflight_update(device, target)

      # A device that does not report `currently_downloading_uuid` on join is
      # taken to be idle, and NervesHub clears any inflight update for it. A
      # device that is mid-download has to say so — which is what
      # `FirmwareMetadata::join_params`'s `currently_downloading_uuid` is for.
      params = esp_join_params(elf_sha256, %{"currently_downloading_uuid" => target.uuid})

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket, params)

      SocketClient.push(socket, "device", "update_progress", %{
        "value" => 42,
        "stage" => "downloading"
      })

      eventually(
        assert(
          %{progress: 42, status: :downloading} =
            Repo.reload!(inflight_update) |> Map.take([:progress, :status])
        )
      )

      SocketClient.clean_close(socket)
    end
  end
end
