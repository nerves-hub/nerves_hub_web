defmodule NervesHub.Devices.RemoveChunkFailureTest do
  @moduledoc """
  What happens when one chunk of a remove from a deployment group fails.

  The failure is a trigger on `devices`. Creating one locks the table against
  other writers until the test's transaction ends, so these run on their own
  rather than alongside the async tests that write devices.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    {:ok, deployment_group} =
      ManagedDeployments.create_deployment_group(
        %{name: "Chunk failure", conditions: %{"version" => "", "tags" => ["keep"]}},
        product,
        firmware,
        user
      )

    device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

    # Two chunks: the first goes in, the second fails
    device_ids = [device.id | insert_devices(org, product, device, 5_000, deployment_group.id)]
    last_id = List.last(device_ids)

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, DeviceEvents.topic(device))

    # The second chunk holds the last id, and its UPDATE is rejected
    fail_updates_to(last_id)

    %{
      deployment_group: deployment_group,
      device: device,
      device_ids: device_ids,
      last_id: last_id,
      product: product
    }
  end

  test "the devices page's remove keeps the chunks before the failure, and tells their devices", context do
    %{device: device, device_ids: device_ids, last_id: last_id, product: product} = context

    assert_raise Postgrex.Error, ~r/simulated failure/, fn ->
      BulkActions.remove_many_from_deployment_group({device_ids, product})
    end

    assert_removed_before_failure(device, last_id, context.deployment_group)
  end

  test "the deployment group page's remove keeps the chunks before the failure, and tells their devices", context do
    %{deployment_group: deployment_group, device: device, last_id: last_id} = context

    # None carry the group's tag, so every device is unmatched
    matched = ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)

    assert_raise Postgrex.Error, ~r/simulated failure/, fn ->
      Deployments.remove_unmatched_devices_from_deployment_group(matched, deployment_group)
    end

    assert_removed_before_failure(device, last_id, deployment_group)
  end

  defp assert_removed_before_failure(device, last_id, deployment_group) do
    topic = DeviceEvents.topic(device)

    refute Repo.reload(device).deployment_id
    assert Repo.get!(Device, last_id).deployment_id == deployment_group.id

    assert_receive %Broadcast{topic: ^topic, event: "deployment_updated", payload: %{deployment_id: nil}}, 1_000
  end

  # Inserts `count` devices like `template` in one statement, since a fixture
  # each would take minutes, and returns their ids
  defp insert_devices(org, product, template, count, deployment_id) do
    now = NaiveDateTime.utc_now(:second)

    rows =
      for n <- 1..count do
        %{
          org_id: org.id,
          product_id: product.id,
          deployment_id: deployment_id,
          identifier: "chunk-failure-#{System.unique_integer([:positive])}-#{n}",
          firmware_metadata: template.firmware_metadata,
          inserted_at: now,
          updated_at: now
        }
      end

    {^count, inserted} = Repo.insert_all(Device, rows, returning: [:id])
    Enum.map(inserted, & &1.id)
  end

  # Makes Postgres reject any UPDATE of `id`'s row. Undone when the test's
  # transaction rolls back.
  defp fail_updates_to(id) do
    Repo.query!("""
    CREATE FUNCTION pg_temp.fail_remove() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'simulated failure';
    END
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER fail_remove BEFORE UPDATE ON devices
    FOR EACH ROW WHEN (OLD.id = #{id})
    EXECUTE FUNCTION pg_temp.fail_remove()
    """)
  end
end
