defmodule NervesHub.Archives.ArchiveTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Archives.Archive

  describe "version SemVer validation" do
    test "create_changeset rejects a non-semver version" do
      changeset = Archive.create_changeset(%Archive{}, %{version: "not-a-version"})
      assert "must be a valid semantic version" in errors_on(changeset).version
    end

    test "create_changeset accepts a valid semver version" do
      changeset = Archive.create_changeset(%Archive{}, %{version: "0.9.0+build.7"})
      refute Map.has_key?(errors_on(changeset), :version)
    end
  end
end
