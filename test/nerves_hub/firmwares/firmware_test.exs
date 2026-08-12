defmodule NervesHub.Firmwares.FirmwareTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares.Firmware

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
end
