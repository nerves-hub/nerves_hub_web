defmodule NervesHubWeb.Live.FirmwareAtomVMTest do
  @moduledoc """
  Uploading an AtomVM packbeam through the browser.

  `atom_vm_upload_test.exs` covers the context layer, and passed while the
  feature was unreachable: `allow_upload` accepted `.fw`, `.bin` and `.raucb`,
  so a `.avm` was rejected in the browser before any of that code ran. Exactly
  what happened to RAUC, in the same place, for the same reason.

  Not async: enabling the tool changes application environment, which is global.
  """

  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Support.AtomVM

  setup do
    original = Application.get_env(:nerves_hub, :atomvm_firmware_enabled)
    Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :atomvm_firmware_enabled, original) end)

    :ok
  end

  describe "upload" do
    test "the file picker accepts packbeams", %{conn: conn, user: user, org: org} do
      product = Fixtures.atomvm_product_fixture(user, org)

      # `accept` reaches the browser as the input's accept attribute, so this is
      # the only place a client-side rejection of .avm would show up.
      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("input[type='file'][accept*='.avm']")
      |> assert_has("input[type='file'][accept*='.fw']")
    end

    test "a packbeam uploaded through the browser becomes firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.atomvm_product_fixture(user, org)

      {:ok, path} =
        AtomVM.create_firmware(product.name, version: "1.4.0", description: "blinks an LED")

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> unwrap(fn view ->
        archive =
          file_input(view, "#firmware-form", :firmware, [
            %{
              last_modified: 1_594_171_879_000,
              name: "blinky-1.4.0.avm",
              content: File.read!(path)
            }
          ])

        render_upload(archive, "blinky-1.4.0.avm")
      end)

      # `allow_upload` rejecting the extension would fail the upload before
      # `handle_progress/3` ran, so reaching the database at all is the point.
      assert [firmware] = Firmwares.get_firmwares_by_product(product.id)

      assert firmware.tool == "atomvm"
      assert firmware.version == "1.4.0"
      assert firmware.platform == "atomvm"
      assert firmware.architecture == "beam"
      assert firmware.description == "blinks an LED"
    end
  end

  describe "index" do
    test "lists a packbeam alongside its tool", %{conn: conn, user: user, org: org} do
      product = Fixtures.atomvm_product_fixture(user, org)
      {:ok, path} = AtomVM.create_firmware(product.name, version: "1.4.0")
      {:ok, firmware} = Firmwares.create_firmware(org, path, product: product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("a", text: firmware.uuid)
      |> assert_has("code", text: "atomvm")
      |> assert_has("td", text: "beam")
    end
  end
end
