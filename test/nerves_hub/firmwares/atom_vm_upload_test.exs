defmodule NervesHub.Firmwares.AtomVMUploadTest do
  @moduledoc """
  Uploading an AtomVM packbeam through the path a real upload takes: format
  detection, the product's allowed formats, signature handling, and the firmware
  record that comes out.
  """
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Support.AtomVM

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    %{user: user, org: org}
  end

  test "records a packbeam with the metadata read from it", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware(product.name, version: "1.4.0", description: "blinks an LED")

    assert {:ok, firmware} = Firmwares.create_firmware(org, path, product: product)

    assert firmware.tool == "atomvm"
    assert firmware.version == "1.4.0"
    assert firmware.platform == "atomvm"
    assert firmware.architecture == "beam"
    assert firmware.description == "blinks an LED"
    assert firmware.product_id == product.id
  end

  # Packbeam carries no signature, so an archive is recorded unsigned rather
  # than being refused for lacking one.
  test "records it with no signing key, without a product opt-in", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    _key = Fixtures.org_key_fixture(org, user)
    {:ok, path} = AtomVM.create_firmware(product.name)

    assert {:ok, firmware} = Firmwares.create_firmware(org, path, product: product)

    assert is_nil(firmware.org_key_id)
    refute product.allow_unsigned_esp_idf_firmware
  end

  # An organization signs AtomVM firmware with the key it already uses for fwup:
  # the public half NervesHub stores is byte for byte the trailing half of an
  # fwup private key.
  test "records the org key that signed the archive", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {public, seed} = AtomVM.keypair()

    org_key =
      %OrgKey{}
      |> OrgKey.changeset(%{
        org_id: org.id,
        created_by_id: user.id,
        name: "atomvm-#{System.unique_integer([:positive])}",
        key: public,
        scheme: :ed25519
      })
      |> NervesHub.Repo.insert!()

    {:ok, path} = AtomVM.create_firmware(product.name, version: "3.0.0", sign_with: seed)

    assert {:ok, firmware} = Firmwares.create_firmware(org, path, product: product)
    assert firmware.org_key_id == org_key.id
  end

  # A signature that does not check out is refused whatever the product allows.
  test "refuses an archive whose signature does not verify", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {_public, seed} = AtomVM.keypair()
    {other, _} = AtomVM.keypair()

    %OrgKey{}
    |> OrgKey.changeset(%{
      org_id: org.id,
      created_by_id: user.id,
      name: "other-#{System.unique_integer([:positive])}",
      key: other,
      scheme: :ed25519
    })
    |> NervesHub.Repo.insert!()

    {:ok, path} = AtomVM.create_firmware(product.name, version: "3.1.0", sign_with: seed)

    assert {:error, :invalid_signature} = Firmwares.create_firmware(org, path, product: product)
  end

  test "refuses a packbeam for a product that has not opted in", %{user: user, org: org} do
    product = Fixtures.product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware(product.name)

    assert {:error, {:update_tool_not_allowed, "atomvm", name}} =
             Firmwares.create_firmware(org, path, product: product)

    assert name == product.name
  end

  test "refuses an archive whose application name is not the product", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware("some_other_app")

    assert {:error, {:product_mismatch, "some_other_app", _}} =
             Firmwares.create_firmware(org, path, product: product)
  end

  test "refuses an archive whose vsn is not a version", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware(product.name, version: "git")

    assert {:error, {:invalid_version, "git"}} = Firmwares.create_firmware(org, path, product: product)
  end

  # `for_file/1` inspects the file rather than trusting the extension, so the
  # three formats an instance may accept do not have to be distinguished by name.
  test "picks the tool by inspecting the file, not its extension", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware(product.name, name: "misnamed")
    renamed = String.replace(path, ".avm", ".fw")
    File.rename!(path, renamed)

    assert {:ok, firmware} = Firmwares.create_firmware(org, renamed, product: product)
    assert firmware.tool == "atomvm"
  end

  # A product that opted in before the instance turned the format off keeps the
  # setting, and its firmware stays readable; only new uploads stop.
  test "is refused while the instance has the format disabled", %{user: user, org: org} do
    product = Fixtures.atomvm_product_fixture(user, org)
    {:ok, path} = AtomVM.create_firmware(product.name)

    Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true) end)

    assert {:error, :unrecognised_firmware_format} = Firmwares.create_firmware(org, path, product: product)
  end
end
