defmodule NervesHubWeb.Live.ScriptRunsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners

  setup %{user: user, org: org} = context do
    product = Fixtures.product_fixture(user, org, %{name: "Amazing"})
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    Map.merge(context, %{product: product, firmware: firmware})
  end

  defp create_run(ctx, opts) do
    tag = Keyword.get(opts, :tag, "run-#{System.unique_integer([:positive])}")
    text = Keyword.get(opts, :text, "IO.puts(:hi)")
    name = Keyword.get(opts, :name, "Run #{System.unique_integer([:positive])}")

    for _ <- 1..Keyword.get(opts, :devices, 1) do
      Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, %{tags: [tag]})
    end

    {:ok, run, []} =
      ScriptRunners.create(ctx.product, ctx.user, %{
        name: name,
        text: text,
        filter_type: Keyword.get(opts, :filter_type, :tags),
        filter: Keyword.get(opts, :filter, %{tags: [tag], tag_operator: :or})
      })

    run
  end

  defp runs_path(ctx), do: "/org/#{ctx.org.name}/#{ctx.product.name}/scripts/runs"

  describe "tabs" do
    test "the scripts page offers both tabs", ctx do
      ctx.conn
      |> visit("/org/#{ctx.org.name}/#{ctx.product.name}/scripts")
      |> within("#header + div", fn session ->
        session
        |> assert_has("a", text: "Support Scripts")
        |> assert_has("a", text: "Script Runs")
      end)
    end

    test "the runs tab is reachable from the scripts tab", ctx do
      ctx.conn
      |> visit("/org/#{ctx.org.name}/#{ctx.product.name}/scripts")
      |> within("#header + div", &click_link(&1, "Script Runs"))
      |> assert_path(runs_path(ctx))
      |> assert_has("h1", text: "All Script Runs")
    end

    test "the scripts tab is reachable from the runs tab", ctx do
      ctx.conn
      |> visit(runs_path(ctx))
      |> within("#header + div", &click_link(&1, "Support Scripts"))
      |> assert_path("/org/#{ctx.org.name}/#{ctx.product.name}/scripts")
      |> assert_has("h1", text: "All Support Scripts")
    end
  end

  describe "list" do
    test "shows a message when there are no runs", ctx do
      ctx.conn
      |> visit(runs_path(ctx))
      |> assert_has("span", text: "#{ctx.product.name} doesn’t have any Script Runs")
    end

    test "shows a run with its name, status, device count and filter type", ctx do
      _run = create_run(ctx, name: "Check uptime", text: "System.cmd(\"uptime\", [])", devices: 3)

      ctx.conn
      |> visit(runs_path(ctx))
      |> assert_has("td", text: "Check uptime")
      |> assert_has("td", text: "pending")
      |> assert_has("td", text: "3")
      |> assert_has("td", text: "Tags")
    end

    test "does not show the script's code, which belongs on the run's own page", ctx do
      _run = create_run(ctx, name: "Check uptime", text: "System.cmd(\"uptime\", [])")

      ctx.conn
      |> visit(runs_path(ctx))
      |> refute_has("td", text: "System.cmd(\"uptime\", [])")
    end

    test "does not show another product's runs", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "Other"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)

      Fixtures.device_fixture(ctx.org, other_product, other_firmware, %{tags: ["theirs"]})

      {:ok, _their_run, []} =
        ScriptRunners.create(other_product, ctx.user, %{
          name: "THEIR RUN",
          text: "THEIR SCRIPT",
          filter_type: :tags,
          filter: %{tags: ["theirs"], tag_operator: :or}
        })

      ctx.conn
      |> visit(runs_path(ctx))
      |> refute_has("td", text: "THEIR RUN")
    end

    test "labels the filter type a run was targeted by", ctx do
      device = Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware)

      _run =
        create_run(ctx,
          name: "By identifiers",
          filter_type: :identifiers,
          filter: %{identifiers: device.identifier}
        )

      ctx.conn
      |> visit(runs_path(ctx))
      |> assert_has("td", text: "Device identifiers")
    end
  end

  describe "filtering" do
    # The search box carries no label, so it is driven through its change event
    # rather than `fill_in/3` — the same way the support scripts test does it.
    test "search filters runs by name", ctx do
      _uptime = create_run(ctx, name: "Check uptime")
      _reboot = create_run(ctx, name: "Reboot everything")

      {:ok, view, html} = live(ctx.conn, runs_path(ctx))

      assert html =~ "Check uptime"
      assert html =~ "Reboot everything"

      filtered = render_change(view, "update-filters", %{"search" => "Reboot"})

      assert filtered =~ "Reboot everything"
      refute filtered =~ "Check uptime"
    end

    test "search does not reach the script contents", ctx do
      _uptime = create_run(ctx, name: "Check uptime", text: "System.cmd(\"uptime\", [])")

      {:ok, view, _html} = live(ctx.conn, runs_path(ctx))

      assert render_change(view, "update-filters", %{"search" => "System.cmd"}) =~
               "No Script Runs match the current filters."
    end

    test "shows a filter-specific message when nothing matches", ctx do
      _run = create_run(ctx, name: "Say hi")

      {:ok, view, _html} = live(ctx.conn, runs_path(ctx))

      assert render_change(view, "update-filters", %{"search" => "nothing-matches-this"}) =~
               "No Script Runs match the current filters."
    end
  end

  describe "run a script button" do
    test "leads to the new run page", ctx do
      ctx.conn
      |> visit(runs_path(ctx))
      |> click_link("Run a Script")
      |> assert_path("#{runs_path(ctx)}/new")
      |> assert_has("h1", text: "Run a Script")
    end
  end
end
