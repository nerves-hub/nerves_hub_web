defmodule NervesHub.Devices.DeviceTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{org: org, product: product, device: device}
  end

  test "changeset/2 adds error when updating a soft-deleted device", %{device: device} do
    deleted_device = %{device | deleted_at: DateTime.utc_now()}
    changeset = Device.changeset(deleted_device, %{description: "new description"})
    assert {:deleted_at, {"cannot update while marked as deleted", []}} in changeset.errors
  end

  test "changeset/2 allows updating deleted_at on a soft-deleted device", %{device: device} do
    deleted_device = %{device | deleted_at: DateTime.utc_now()}
    changeset = Device.changeset(deleted_device, %{deleted_at: nil})
    refute Keyword.has_key?(changeset.errors, :deleted_at)
  end

  describe "create_changeset/2" do
    test "takes the org and product from the product, whatever the params say", %{product: product} do
      changeset =
        Device.create_changeset(product, %{
          "identifier" => "new-device",
          "description" => "added by a user",
          "org_id" => -1,
          "product_id" => -1,
          "deployment_id" => -1,
          "status" => "provisioned"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :org_id) == product.org_id
      assert Ecto.Changeset.get_field(changeset, :product_id) == product.id
      assert Ecto.Changeset.get_field(changeset, :description) == "added by a user"
      assert Ecto.Changeset.get_field(changeset, :deployment_id) == nil
      assert Ecto.Changeset.get_field(changeset, :status) == :registered
    end

    test "starts the device with the product's managed updates grant", %{product: product} do
      product = %{product | default_managed_updates_allowed: true}
      changeset = Device.create_changeset(product, %{"identifier" => "new-device", "managed_updates_allowed" => false})

      assert Ecto.Changeset.get_field(changeset, :managed_updates_allowed)
    end
  end

  describe "update_changeset/2" do
    test "changes only what a user may set", %{device: device} do
      changeset =
        Device.update_changeset(device, %{
          "description" => "changed",
          "tags" => "a, b",
          "update_mode" => "off",
          "connecting_code" => "IO.puts(1)",
          "identifier" => "renamed",
          "org_id" => -1,
          "product_id" => -1,
          "deployment_id" => -1,
          "deleted_at" => DateTime.utc_now()
        })

      # The update mode is left to `cast_update_mode/2`: changing it goes through
      # `Updates.save_update_mode/3`.
      assert Map.keys(changeset.changes) |> Enum.sort() == [:connecting_code, :description, :tags]
    end

    test "refuses a soft-deleted device", %{device: device} do
      deleted_device = %{device | deleted_at: DateTime.utc_now()}
      changeset = Device.update_changeset(deleted_device, %{"description" => "new description"})

      assert {:deleted_at, {"cannot update while marked as deleted", []}} in changeset.errors
    end
  end

  describe "cast_update_mode/2" do
    test "returns the mode asked for", %{device: device} do
      assert Device.cast_update_mode(device, %{"update_mode" => "device_managed"}) == {:ok, :device_managed}
    end

    test "returns nil when the params ask for no change", %{device: device} do
      assert device.update_mode == :automatic
      assert Device.cast_update_mode(device, %{"description" => "changed"}) == {:ok, nil}
      assert Device.cast_update_mode(device, %{"update_mode" => "automatic"}) == {:ok, nil}
    end

    test "refuses a value that isn't a mode", %{device: device} do
      assert {:error, changeset} = Device.cast_update_mode(device, %{"update_mode" => "sometimes"})
      assert [update_mode: {"is invalid", _}] = changeset.errors

      assert {:error, changeset} = Device.cast_update_mode(device, %{"update_mode" => nil})
      assert [update_mode: {"can't be blank", _}] = changeset.errors
    end
  end
end
