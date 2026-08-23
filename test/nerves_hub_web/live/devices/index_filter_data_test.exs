defmodule NervesHubWeb.Live.Devices.IndexFilterDataTest do
  # Not async: counts repo queries via telemetry, which is process-global.
  use NervesHubWeb.ConnCase.Browser, async: false
  use AssertEventually, timeout: 2000, interval: 50

  import Phoenix.LiveViewTest

  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Filter Data"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    _device = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})

    %{product: product}
  end

  # Sorting and paging re-run `handle_params/3`, which used to re-run all of the
  # filter dropdown queries even though they only depend on the product.
  test "filter data is loaded once, not on every navigation", %{conn: conn, org: org, product: product} do
    counter = start_counter()
    path = "/org/#{org.name}/#{product.name}/devices"

    {:ok, view, _html} = live(conn, path)

    # Both the device list and the filter data are requested from mount.
    assert_eventually(count(counter, :device_list) == 1)
    assert_eventually(count(counter, :filter_data) == 1)

    _ = render_patch(view, path <> "?sort=identifier&sort_direction=desc")
    assert_eventually(count(counter, :device_list) == 2)

    _ = render_patch(view, path <> "?page_number=1&page_size=50")
    assert_eventually(count(counter, :device_list) == 3)

    # The device list was re-queried twice more, so anything `handle_params/3`
    # dispatched alongside it has had its chance to run.
    assert count(counter, :filter_data) == 1
  end

  defp start_counter() do
    counter = :counters.new(2, [])
    handler_id = "filter-data-counter-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:nerves_hub, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        cond do
          # `Devices.distinct_tags/1`, one of the eight filter dropdown queries
          String.contains?(query, "DISTINCT unnest") ->
            :counters.add(counter, 2, 1)

          # the paginated device list itself
          String.contains?(query, ~s|FROM "devices" AS d0 LEFT OUTER JOIN|) and
              String.contains?(query, "LIMIT") ->
            :counters.add(counter, 1, 1)

          true ->
            :ok
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    counter
  end

  defp count(counter, :device_list), do: :counters.get(counter, 1)
  defp count(counter, :filter_data), do: :counters.get(counter, 2)
end
