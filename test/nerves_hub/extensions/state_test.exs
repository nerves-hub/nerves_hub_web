defmodule NervesHub.Extensions.StateTest do
  use ExUnit.Case, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.State

  defp device_info() do
    %DeviceInfo{device_id: 1, device_identifier: "test-device"}
  end

  describe "new/1" do
    test "builds empty state from DeviceInfo" do
      info = device_info()
      state = State.new(info)

      assert state.device_info == info
      assert state.assigns == %{}
    end
  end

  describe "assign/3" do
    test "stores a value under the given key" do
      state = State.new(device_info())
      state = State.assign(state, :my_key, "my_value")

      assert state.assigns[:my_key] == "my_value"
    end

    test "overwrites an existing key" do
      state = State.new(device_info())
      state = State.assign(state, :counter, 1)
      state = State.assign(state, :counter, 2)

      assert state.assigns[:counter] == 2
    end

    test "stores multiple keys independently" do
      state =
        State.new(device_info())
        |> State.assign(:a, 1)
        |> State.assign(:b, 2)

      assert state.assigns[:a] == 1
      assert state.assigns[:b] == 2
    end
  end

  describe "get/3" do
    test "retrieves a stored value" do
      state = State.new(device_info()) |> State.assign(:foo, :bar)

      assert State.get(state, :foo) == :bar
    end

    test "returns nil default when key is absent" do
      state = State.new(device_info())

      assert State.get(state, :missing) == nil
    end

    test "returns given default when key is absent" do
      state = State.new(device_info())

      assert State.get(state, :missing, :default_val) == :default_val
    end

    test "does not return default when key is present with nil value" do
      state = State.new(device_info()) |> State.assign(:nullable, nil)

      assert State.get(state, :nullable, :fallback) == nil
    end
  end
end
