defmodule NervesHub.Firmwares.FirmwareTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "version SemVer validation" do
    test "create_changeset rejects a non-semver version" do
      changeset = Firmware.create_changeset(%Firmware{}, %{version: "not-a-version"})
      assert "must be a valid semantic version" in errors_on(changeset).version
    end

    test "create_changeset rejects a partial version" do
      changeset = Firmware.create_changeset(%Firmware{}, %{version: "1.2"})
      assert "must be a valid semantic version" in errors_on(changeset).version
    end

    test "create_changeset accepts a valid semver version" do
      changeset = Firmware.create_changeset(%Firmware{}, %{version: "1.2.3-rc.1"})
      refute Map.has_key?(errors_on(changeset), :version)
    end

    test "update_changeset rejects a non-semver version" do
      changeset = Firmware.update_changeset(%Firmware{}, %{version: "latest"})
      assert "must be a valid semantic version" in errors_on(changeset).version
    end
  end

  # `org_key_id` was NOT NULL from 2018 (`firmware_must_be_signed`). A product
  # may now allow unsigned ESP-IDF images, and that rule lives in `products` —
  # it cannot be expressed as a constraint on this table. So the database holds
  # the guarantee for fwup and defers to the application for ESP-IDF.
  describe "signing is enforced by the database for fwup" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, %{firmware: firmware}}
    end

    test "an fwup firmware cannot be left unsigned", %{firmware: firmware} do
      assert firmware.tool == "fwup"

      assert_raise Postgrex.Error, ~r/firmwares_signed_unless_optional_format/, fn ->
        Firmware
        |> where(id: ^firmware.id)
        |> Repo.update_all(set: [org_key_id: nil])
      end
    end

    test "an esp-idf firmware may be unsigned", %{firmware: firmware} do
      assert {1, _} =
               Firmware
               |> where(id: ^firmware.id)
               |> Repo.update_all(set: [tool: "esp-idf", org_key_id: nil])
    end

    # Nothing signs a packbeam today, so an AtomVM firmware is always stored
    # without a key rather than sometimes.
    test "an atomvm firmware may be unsigned", %{firmware: firmware} do
      assert {1, _} =
               Firmware
               |> where(id: ^firmware.id)
               |> Repo.update_all(set: [tool: "atomvm", org_key_id: nil])
    end

    # `tool` is nullable, so `IN (...)` would evaluate to NULL here and a
    # CHECK passes on NULL. `IS NOT DISTINCT FROM` is what closes that.
    test "a firmware with no tool cannot be left unsigned either", %{firmware: firmware} do
      assert_raise Postgrex.Error, ~r/firmwares_signed_unless_optional_format/, fn ->
        Firmware
        |> where(id: ^firmware.id)
        |> Repo.update_all(set: [tool: nil, org_key_id: nil])
      end
    end
  end
end
