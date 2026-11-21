defmodule NervesHub.DeviceLink.DeviceInfoTest do
  use ExUnit.Case, async: true

  alias NervesHub.DeviceLink.DeviceInfo

  describe "trace_attributes/1" do
    test "is the device's, product's and organization's ids" do
      assert DeviceInfo.trace_attributes(%DeviceInfo{device_id: 1, product_id: 2, org_id: 3, device_identifier: "abc"}) ==
               %{"nerves_hub.device.id": 1, "nerves_hub.product.id": 2, "nerves_hub.org.id": 3}
    end

    test "leaves out an id the device doesn't have" do
      assert DeviceInfo.trace_attributes(%DeviceInfo{device_id: 1}) == %{"nerves_hub.device.id": 1}
    end
  end
end
