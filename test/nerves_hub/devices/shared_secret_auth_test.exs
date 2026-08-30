defmodule NervesHub.Devices.SharedSecretAuthTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, device: device}
  end

  describe "create_changeset/2" do
    test "produces a valid changeset", %{device: device} do
      changeset = SharedSecretAuth.create_changeset(device)
      assert changeset.valid?
    end

    test "key has the nhd_ prefix format", %{device: device} do
      changeset = SharedSecretAuth.create_changeset(device)
      key = Ecto.Changeset.get_change(changeset, :key)
      assert key =~ ~r/^nhd_[a-zA-Z0-9\-\/\+]{43}$/
    end

    test "secret matches expected format", %{device: device} do
      changeset = SharedSecretAuth.create_changeset(device)
      secret = Ecto.Changeset.get_change(changeset, :secret)
      assert secret =~ ~r/^[a-zA-Z0-9\-\/\+]{43}$/
    end

    test "two changesets get different keys and secrets", %{device: device} do
      cs1 = SharedSecretAuth.create_changeset(device)
      cs2 = SharedSecretAuth.create_changeset(device)

      key1 = Ecto.Changeset.get_change(cs1, :key)
      key2 = Ecto.Changeset.get_change(cs2, :key)
      secret1 = Ecto.Changeset.get_change(cs1, :secret)
      secret2 = Ecto.Changeset.get_change(cs2, :secret)

      assert key1 != key2
      assert secret1 != secret2
    end

    test "changeset has no errors", %{device: device} do
      changeset = SharedSecretAuth.create_changeset(device)
      assert changeset.errors == []
    end
  end

  describe "deactivate_changeset/1" do
    test "sets deactivated_at to a non-nil datetime", %{device: device} do
      auth = %SharedSecretAuth{
        device_id: device.id,
        key: "nhd_somekey",
        secret: "somesecret"
      }

      changeset = SharedSecretAuth.deactivate_changeset(auth)
      deactivated_at = Ecto.Changeset.get_change(changeset, :deactivated_at)
      assert deactivated_at != nil
      assert %DateTime{} = deactivated_at
    end

    test "changeset is valid", %{device: device} do
      auth = %SharedSecretAuth{
        device_id: device.id,
        key: "nhd_somekey",
        secret: "somesecret"
      }

      changeset = SharedSecretAuth.deactivate_changeset(auth)
      assert changeset.valid?
    end
  end
end
