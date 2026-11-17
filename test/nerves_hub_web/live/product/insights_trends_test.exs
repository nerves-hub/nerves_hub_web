defmodule NervesHubWeb.Live.Product.InsightsTrendsTest do
  # Not async: the trends row reads the AnalyticsRepo (ClickHouse).
  use NervesHubWeb.ConnCase.Browser, async: false

  import Ecto.Query

  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Trends"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    Fixtures.device_fixture(org, product, firmware)

    # uploaded three days ago, so the 14 day period shows its release
    uploaded =
      DateTime.utc_now() |> DateTime.add(-3 * 86_400, :second) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    Repo.update_all(from(f in Firmware, where: f.id == ^firmware.id), set: [inserted_at: uploaded])

    %{product: product, firmware: firmware}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  defp click(session, selector), do: unwrap(session, &render_click(element(&1, selector)))

  test "switch the period", %{conn: conn} = ctx do
    conn
    |> visit(insights_path(ctx.org, ctx.product))
    |> assert_has("#trends h2", text: "Last 14 days")
    |> click("#trends-period button[value='4w']")
    |> assert_has("#trends h2", text: "Last 4 weeks")
    |> assert_has("#trends-period button[value='4w'][aria-pressed=true]")
  end

  test "switch the adoption chart between stacked bands and lines", %{conn: conn} = ctx do
    conn
    |> visit(insights_path(ctx.org, ctx.product))
    |> assert_has("#adoption-view button[value=stacked][aria-pressed=true]")
    |> click("#adoption-view button[value=lines]")
    |> assert_has("#adoption-view button[value=lines][aria-pressed=true]")
  end

  test "mark the release, until release annotations are turned off", %{conn: conn} = ctx do
    conn
    |> visit(insights_path(ctx.org, ctx.product))
    |> assert_has("#trends-release", text: "#{ctx.firmware.version} released")
    |> assert_has("#release-annotations[aria-checked=true]")
    |> click("#release-annotations")
    |> assert_has("#release-annotations[aria-checked=false]")
    |> refute_has("#trends-release")
    |> click("#release-annotations")
    |> assert_has("#trends-release")
  end

  test "date the release in the viewer's time zone", %{conn: conn} = ctx do
    # 20:00 UTC is the next morning in Auckland
    released =
      DateTime.utc_now()
      |> DateTime.add(-3 * 86_400, :second)
      |> Map.merge(%{hour: 20, minute: 0, second: 0, microsecond: {0, 0}})

    Repo.update_all(from(f in Firmware, where: f.id == ^ctx.firmware.id),
      set: [inserted_at: DateTime.to_naive(released)]
    )

    local = released |> DateTime.shift_zone!("Pacific/Auckland") |> Calendar.strftime("%b %-d")
    refute local == Calendar.strftime(released, "%b %-d")

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"time_zone" => "Pacific/Auckland"})
      |> live(insights_path(ctx.org, ctx.product))

    assert has_element?(view, "#trends-release", "released #{local}")
  end

  test "leave the trends off the first, unconnected render", %{conn: conn} = ctx do
    html = conn |> get(insights_path(ctx.org, ctx.product)) |> html_response(200)

    refute html =~ ~s(id="trends")

    conn
    |> visit(insights_path(ctx.org, ctx.product))
    |> assert_has("#trends")
  end

  describe "when analytics is disabled" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
      :ok
    end

    test "leave the trends out", %{conn: conn} = ctx do
      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> assert_has("#version-health")
      |> refute_has("#trends")
    end
  end
end
