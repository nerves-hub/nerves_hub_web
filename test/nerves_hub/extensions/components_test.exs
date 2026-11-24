defmodule NervesHub.Extensions.ComponentsTest do
  @moduledoc """
  The components extension: asking for the set, taking it, and what the
  platform does when it has to drop one.

  Storage is `NervesHub.Devices.ComponentsTest`'s subject; this is about the
  protocol around it.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Components, as: Store
  alias NervesHub.Extensions.Components
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_component_history") end)

    %{device: device, state: State.new(device_info)}
  end

  @mcu %{"namespace" => "mcu", "vendor" => "raspberrypi", "model" => "rp2350", "serial" => "e6614c311b4a2c2f"}

  test "asks for the whole set as it attaches", %{state: state} do
    assert {_state, [{:push, "components:sync", %{}}]} = Components.attach(state)
  end

  test "stores a snapshot", %{device: device, state: state} do
    {_state, []} = Components.handle_in("snapshot", %{"components" => [@mcu]}, state)

    assert [%{namespace: "mcu", model: "rp2350"}] = Store.list_for_device(device)
  end

  test "a rejected snapshot changes nothing, and costs no token", %{device: device, state: state} do
    {_state, []} = Components.handle_in("snapshot", %{"components" => [@mcu]}, state)
    {_state, []} = Components.handle_in("snapshot", %{"components" => [@mcu, %{"namespace" => "mcu"}]}, state)

    assert [%{listed: true}] = Store.list_for_device(device)
  end

  test "a snapshot over the limit schedules one sync", %{state: state} do
    snapshot = %{"components" => [@mcu]}

    {state, []} = Components.handle_in("snapshot", snapshot, state)
    {state, []} = Components.handle_in("snapshot", snapshot, state)
    {state, []} = Components.handle_in("snapshot", snapshot, state)

    resync_ms = Components.resync_delay_ms()
    {state, [{:start_timer, :resync, ^resync_ms}]} = Components.handle_in("snapshot", snapshot, state)
    {state, []} = Components.handle_in("snapshot", snapshot, state)

    assert {_state, [{:cancel_timer, :resync}, {:push, "components:sync", %{}}]} =
             Components.handle_info(:resync, state)
  end

  test "a request from the web UI asks the device to look again", %{state: state} do
    assert {^state, [{:push, "components:sync", %{"refresh" => true}}]} = Components.handle_info(:refresh, state)
  end

  test "an event 0.1.0 doesn't have is ignored", %{state: state} do
    assert {^state, []} = Components.handle_in("added", @mcu, state)
  end
end
