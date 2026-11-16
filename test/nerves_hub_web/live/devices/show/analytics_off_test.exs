defmodule NervesHubWeb.Live.Devices.Show.AnalyticsOffTest do
  @moduledoc """
  Without `:analytics_enabled`, `NervesHub.AnalyticsRepo` is never started
  (see `NervesHub.Application.ecto_repos/0`), so any read the device page
  makes from ClickHouse crashes it.

  The test suite starts ClickHouse with analytics on, and turning the flag off
  mid-test leaves it running, so a read that skips the check still succeeds
  here and a test that only looks at the page can't catch it. These tests
  listen for the queries themselves instead.
  """

  # Not async: the listener hears every ClickHouse query on the node, so an
  # async test's queries would count against this one.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Metrics
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  # Every tab, and the views within one that read something else.
  @tabs [
    "",
    "/health",
    "/firmware_history",
    "/firmware_history?view=attempts",
    "/console",
    "/local_shell",
    "/logs",
    "/errors",
    "/activity",
    "/data_history",
    "/settings"
  ]

  @extensions ~w(health metrics alarms geo local_shell logging network_identity error_reports)

  setup %{product: product} do
    original = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

    # Every extension on, so each tab draws its content rather than a notice
    # that the product has it turned off.
    {:ok, product} =
      product
      |> Product.changeset(%{"extensions" => Map.new(@extensions, &{&1, true})})
      |> Repo.update()

    %{product: product}
  end

  test "no tab reads ClickHouse", %{conn: conn, org: org, product: product, device: device} do
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    # Latest metrics live in Postgres, so the Health tab has charts to draw.
    {:ok, _count} = Metrics.record(device_info(device), %{"cpu_temp" => 41.4, "mem_used_percent" => 2})

    listen_for_clickhouse_reads()

    for tab <- @tabs do
      conn
      |> visit(device_path(org, product, device) <> tab)
      |> unwrap(&render_async/1)
    end

    assert clickhouse_reads() == []
  end

  # Without this, a listener that heard nothing would pass the test above.
  test "the listener hears ClickHouse reads", %{conn: conn, org: org, product: product, device: device} do
    Application.put_env(:nerves_hub, :analytics_enabled, true)

    listen_for_clickhouse_reads()

    conn
    |> visit(device_path(org, product, device) <> "/logs")
    |> unwrap(&render_async/1)

    assert clickhouse_reads() != []
  end

  defp device_path(org, product, device), do: "/org/#{org.name}/#{product.name}/devices/#{device.identifier}"

  defp device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  # Reads only: the analytics buffers flush writes from earlier tests on their
  # own schedule.
  defp listen_for_clickhouse_reads() do
    test = self()
    handler_id = "clickhouse-reads-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:nerves_hub, :analytics_repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if query =~ ~r/^\s*SELECT/i, do: send(test, {:clickhouse_read, query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp clickhouse_reads(reads \\ []) do
    receive do
      {:clickhouse_read, query} -> clickhouse_reads([query | reads])
    after
      0 -> Enum.reverse(reads)
    end
  end
end
