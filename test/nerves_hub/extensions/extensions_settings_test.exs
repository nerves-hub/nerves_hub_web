defmodule NervesHub.Extensions.ExtensionsSettingsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Extensions.DeviceExtensionsSetting
  alias NervesHub.Extensions.ProductExtensionsSetting

  describe "DeviceExtensionsSetting Access behaviour" do
    test "fetch/2 returns value for existing key" do
      setting = %DeviceExtensionsSetting{}
      assert {:ok, true} = DeviceExtensionsSetting.fetch(setting, :health)
    end

    test "pop/2 removes key and returns value" do
      setting = %DeviceExtensionsSetting{health: true}
      {value, updated} = DeviceExtensionsSetting.pop(setting, :health)
      assert value == true
      refute Map.has_key?(updated, :health)
    end

    test "get_and_update/3 updates value and returns old value" do
      setting = %DeviceExtensionsSetting{health: true}

      {old, updated} =
        DeviceExtensionsSetting.get_and_update(setting, :health, fn current ->
          {current, false}
        end)

      assert old == true
      assert updated.health == false
    end
  end

  describe "ProductExtensionsSetting Access behaviour" do
    test "fetch/2 returns value for existing key" do
      setting = %ProductExtensionsSetting{}
      assert {:ok, false} = ProductExtensionsSetting.fetch(setting, :health)
    end

    test "pop/2 removes key and returns value" do
      setting = %ProductExtensionsSetting{geo: false}
      {value, updated} = ProductExtensionsSetting.pop(setting, :geo)
      assert value == false
      refute Map.has_key?(updated, :geo)
    end

    test "get_and_update/3 updates value and returns old value" do
      setting = %ProductExtensionsSetting{logging: false}

      {old, updated} =
        ProductExtensionsSetting.get_and_update(setting, :logging, fn current ->
          {current, true}
        end)

      assert old == false
      assert updated.logging == true
    end
  end
end
