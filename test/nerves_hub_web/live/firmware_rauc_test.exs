defmodule NervesHubWeb.Live.FirmwareRaucTest do
  @moduledoc """
  Uploading a RAUC bundle through the browser.

  `rauc_upload_test.exs` covers the context layer, and passed while the feature
  was unreachable: `allow_upload` accepted only `.fw` and `.bin`, so a `.raucb`
  was rejected in the browser before any of that code ran. Only a test that goes
  through the LiveView can see that.

  Not async: enabling the tool changes application environment, which is global.
  """

  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Products

  @bundle Path.expand("../../fixtures/rauc/verity-1.13.raucb", __DIR__)
  @signer Path.expand("../../fixtures/rauc/signer-1.13.pem", __DIR__)

  setup do
    original = Application.get_env(:nerves_hub, :rauc_firmware_enabled)
    Application.put_env(:nerves_hub, :rauc_firmware_enabled, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :rauc_firmware_enabled, original) end)

    :ok
  end

  # Named to match `[meta.nerveshub] product` in the fixture bundle: NervesHub
  # refuses firmware whose declared product is not the one it was uploaded to.
  defp rauc_product(user, org) do
    product = Fixtures.product_fixture(user, org, %{name: "Gateway"})
    {:ok, product} = Products.update_product(product, %{allowed_update_tools: ["fwup", "rauc"]})
    product
  end

  defp register_signer(org, user) do
    {:ok, org_key} =
      NervesHub.Accounts.create_org_key(%{
        org_id: org.id,
        created_by_id: user.id,
        name: "rauc-#{System.unique_integer([:positive])}",
        key: File.read!(@signer),
        scheme: :x509_certificate
      })

    org_key
  end

  describe "upload" do
    test "the file picker accepts RAUC bundles", %{conn: conn, user: user, org: org} do
      product = rauc_product(user, org)

      # `accept` reaches the browser as the input's accept attribute, so this is
      # the only place a client-side rejection of .raucb would show up.
      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("input[type='file'][accept*='.raucb']")
      |> assert_has("input[type='file'][accept*='.fw']")
    end

    test "a bundle uploaded through the browser becomes firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = rauc_product(user, org)
      org_key = register_signer(org, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> unwrap(fn view ->
        bundle =
          file_input(view, "#firmware-form", :firmware, [
            %{
              last_modified: 1_594_171_879_000,
              name: "gateway-1.4.2.raucb",
              content: File.read!(@bundle)
            }
          ])

        render_upload(bundle, "gateway-1.4.2.raucb")
      end)

      # `allow_upload` rejecting the extension would fail the upload before
      # `handle_progress/3` ran, so reaching the database at all is the point.
      assert [firmware] = Firmwares.get_firmwares_by_product(product.id)

      assert firmware.tool == "rauc"
      assert firmware.version == "1.4.2"
      assert firmware.architecture == "aarch64"
      assert firmware.uuid == "65547c89-8185-3d08-7e73-551be4c47401"
      assert firmware.org_key_id == org_key.id
    end
  end
end
