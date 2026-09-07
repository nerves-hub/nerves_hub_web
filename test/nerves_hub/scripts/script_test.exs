defmodule NervesHub.Scripts.ScriptTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Scripts.Script

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    %{user: user, product: product}
  end

  test "update_changeset/3 returns a valid changeset", %{user: user, product: product} do
    script = %Script{name: "old name", text: "echo hello", product_id: product.id, created_by_id: user.id}

    changeset = Script.update_changeset(script, user, %{name: "new name", text: "echo world"})
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :name) == "new name"
    assert changeset.changes[:last_updated_by_id] == user.id
  end

  test "update_changeset/3 with missing required fields is invalid", %{user: user} do
    script = %Script{name: "old name", text: "echo hello"}
    changeset = Script.update_changeset(script, user, %{name: ""})
    refute changeset.valid?
  end
end
