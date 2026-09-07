defmodule NervesHub.Firmwares.FirmwareDeltaTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares.FirmwareDelta

  test "start_changeset/3 returns a valid changeset" do
    changeset = FirmwareDelta.start_changeset(%FirmwareDelta{}, 1, 2)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :status) == :processing
    assert Ecto.Changeset.get_change(changeset, :source_id) == 1
    assert Ecto.Changeset.get_change(changeset, :target_id) == 2
  end

  test "start_changeset/2 uses default FirmwareDelta struct" do
    changeset = FirmwareDelta.start_changeset(10, 20)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :tool) == "pending"
  end
end
