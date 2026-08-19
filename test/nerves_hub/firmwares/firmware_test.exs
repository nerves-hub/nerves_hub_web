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

  # `org_key_id` has been NOT NULL since 2018 (`firmware_must_be_signed`). It
  # was briefly nullable while ESP-IDF images could not be signature-verified;
  # now that they can, every format is signed and the column is NOT NULL again.
  describe "signing is enforced by the database" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, %{firmware: firmware}}
    end

    test "no firmware may be left unsigned", %{firmware: firmware} do
      assert_raise Postgrex.Error, ~r/org_key_id/, fn ->
        Firmware
        |> where(id: ^firmware.id)
        |> Repo.update_all(set: [org_key_id: nil])
      end
    end

    # Including ESP-IDF, which was the one exception while verification was
    # unimplemented.
    test "not even an esp-idf firmware", %{firmware: firmware} do
      assert_raise Postgrex.Error, ~r/org_key_id/, fn ->
        Firmware
        |> where(id: ^firmware.id)
        |> Repo.update_all(set: [tool: "esp-idf", org_key_id: nil])
      end
    end
  end
end
