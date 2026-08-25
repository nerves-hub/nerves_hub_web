defmodule NervesHub.Extensions.NetworkIdentityTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.NetworkIdentity
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: org.id,
      product_id: product.id
    }

    %{state: State.new(device_info), device: device}
  end

  describe "description/0" do
    test "returns a non-empty string" do
      assert is_binary(NetworkIdentity.description())
      assert String.length(NetworkIdentity.description()) > 0
    end
  end

  describe "enabled?/0" do
    test "returns true" do
      assert NetworkIdentity.enabled?() == true
    end
  end

  describe "attach/1" do
    test "returns state with a tick :request effect" do
      state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
      {new_state, effects} = NetworkIdentity.attach(state)

      assert new_state == state
      assert [{:tick, :request}] = effects
    end
  end

  describe "detach/1" do
    test "returns state with empty effects" do
      state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
      {new_state, effects} = NetworkIdentity.detach(state)

      assert new_state == state
      assert effects == []
    end
  end

  describe "handle_info/2 :request" do
    test "pushes network_identity:request" do
      state = State.new(%DeviceInfo{device_id: 1, device_identifier: "x"})
      {new_state, effects} = NetworkIdentity.handle_info(:request, state)

      assert new_state == state
      assert [{:push, "network_identity:request", %{}}] = effects
    end
  end

  describe "handle_in/3 report with valid list" do
    test "records identities and returns empty effects", %{state: state} do
      identities = [
        %{"service" => "iroh", "identifier" => "abc123", "details" => %{}}
      ]

      {new_state, effects} = NetworkIdentity.handle_in("report", %{"identities" => identities}, state)
      assert new_state == state
      assert effects == []
    end

    test "handles an empty identity list", %{state: state} do
      {new_state, effects} = NetworkIdentity.handle_in("report", %{"identities" => []}, state)
      assert new_state == state
      assert effects == []
    end

    test "skips entries with missing fields (logs warning)", %{state: state} do
      identities = [%{"service" => "iroh"}]

      {new_state, effects} = NetworkIdentity.handle_in("report", %{"identities" => identities}, state)
      assert new_state == state
      assert effects == []
    end

    test "caps at 10 identities", %{state: state} do
      identities =
        for i <- 1..15 do
          %{"service" => "svc#{i}", "identifier" => "id#{i}"}
        end

      {new_state, effects} = NetworkIdentity.handle_in("report", %{"identities" => identities}, state)
      assert new_state == state
      assert effects == []
    end
  end

  describe "handle_in/3 report with malformed payload" do
    test "logs warning and returns empty effects for non-list payload", %{state: state} do
      {new_state, effects} = NetworkIdentity.handle_in("report", %{"identities" => "bad"}, state)
      assert new_state == state
      assert effects == []
    end

    test "handles completely missing identities key", %{state: state} do
      {new_state, effects} = NetworkIdentity.handle_in("report", %{}, state)
      assert new_state == state
      assert effects == []
    end
  end
end
