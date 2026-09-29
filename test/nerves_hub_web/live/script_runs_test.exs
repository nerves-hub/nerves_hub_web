defmodule NervesHubWeb.Live.ScriptRunsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunnerDevice

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

  describe "the new run form" do
    defp new_path(ctx), do: "#{runs_path(ctx)}/new"

    test "offers the general and targeting sections", ctx do
      ctx.conn
      |> visit(new_path(ctx))
      |> assert_has("div", text: "General settings")
      |> assert_has("div", text: "Target devices")
      |> assert_has("button", text: "Run script")
    end

    test "the targeting fields follow the chosen filter type", ctx do
      {:ok, view, html} = live(ctx.conn, new_path(ctx))

      # Nothing is chosen on arrival, so no filter values are asked for yet.
      assert html =~ "Pick a filter to choose which devices this runs on."

      # Each filter type's label is also an option of the filter select, so the
      # inputs are asserted on by their form name rather than by label text.
      tags = render_change(view, "validate", %{"script_runner" => %{"filter_type" => "tags"}})

      assert tags =~ "script_runner[filter][tags]"
      assert tags =~ "script_runner[filter][tag_operator]"
      refute tags =~ "script_runner[filter][identifiers]"

      identifiers = render_change(view, "validate", %{"script_runner" => %{"filter_type" => "identifiers"}})

      assert identifiers =~ "script_runner[filter][identifiers]"
      refute identifiers =~ "script_runner[filter][tag_operator]"

      groups = render_change(view, "validate", %{"script_runner" => %{"filter_type" => "deployment_groups"}})

      assert groups =~ "script_runner[filter][deployment_group_ids]"
      refute groups =~ "script_runner[filter][tags]"
    end

    test "starts a run against tagged devices", ctx do
      Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, %{tags: ["cellular"]})

      ctx.conn
      |> visit(new_path(ctx))
      |> fill_in("Name", with: "Reboot the cellular fleet")
      |> fill_in("Script code", with: "Nerves.Runtime.reboot()")
      |> select("Choose devices by", option: "Tags")
      |> fill_in("Device tags", with: "cellular")
      |> select("Tag matching", option: "Allow any")
      |> click_button("Run script")
      |> assert_path(runs_path(ctx))
      |> assert_has("td", text: "Reboot the cellular fleet")
    end

    test "the script picker offers only this product's scripts, and starting blank", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "Somewhere else"})

      Fixtures.support_script_fixture(ctx.product, ctx.user, %{name: "Reboot device"})
      Fixtures.support_script_fixture(other_product, ctx.user, %{name: "Another product's script"})

      ctx.conn
      |> visit(new_path(ctx))
      |> within("#copy-from-script", fn session ->
        session
        |> assert_has("option", text: "Choose from below")
        |> assert_has("option", text: "Reboot device")
        |> refute_has("option", text: "Another product's script")
      end)
    end

    test "copying a support script fills in its code and name", ctx do
      Fixtures.support_script_fixture(ctx.product, ctx.user, %{
        name: "Reboot device",
        text: "Nerves.Runtime.reboot()"
      })

      ctx.conn
      |> visit(new_path(ctx))
      |> select("Start from a support script", option: "Reboot device")
      |> assert_has("textarea#script_runner_text", text: "Nerves.Runtime.reboot()")
      |> assert_has("input#script_runner_name[value='Reboot device']")
    end

    test "copying a support script keeps a name the run already has", ctx do
      Fixtures.support_script_fixture(ctx.product, ctx.user, %{
        name: "Reboot device",
        text: "Nerves.Runtime.reboot()"
      })

      ctx.conn
      |> visit(new_path(ctx))
      |> fill_in("Name", with: "Reboot the cellular fleet")
      |> select("Start from a support script", option: "Reboot device")
      |> assert_has("textarea#script_runner_text", text: "Nerves.Runtime.reboot()")
      |> assert_has("input#script_runner_name[value='Reboot the cellular fleet']")
    end

    test "a filter matching no device is reported rather than started", ctx do
      {:ok, view, _html} = live(ctx.conn, new_path(ctx))

      submitted =
        render_submit(view, "create-run", %{
          "script_runner" => %{
            "name" => "Nobody home",
            "text" => "IO.puts(:hi)",
            "filter_type" => "tags",
            "filter" => %{"tags" => "nobody-has-this", "tag_operator" => "or"}
          }
        })

      assert submitted =~ "No devices matched the filter"
    end

    test "a tags run without an operator is rejected", ctx do
      Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, %{tags: ["cellular"]})

      {:ok, view, _html} = live(ctx.conn, new_path(ctx))

      submitted =
        render_submit(view, "create-run", %{
          "script_runner" => %{
            "name" => "No operator",
            "text" => "IO.puts(:hi)",
            "filter_type" => "tags",
            "filter" => %{"tags" => "cellular"}
          }
        })

      assert submitted =~ "a tag operator must be chosen"
    end
  end

  describe "identifiers from a CSV" do
    @describetag :tmp_dir

    defp choose_identifiers(session) do
      select(session, "Choose devices by", option: "Device identifiers")
    end

    defp choose_csv(session) do
      choose(session, "Upload a CSV")
    end

    defp csv(tmp_dir, name, contents) do
      path = Path.join(tmp_dir, name)
      :ok = File.write(path, contents)
      path
    end

    test "typing and uploading are alternatives, never both at once", ctx do
      session =
        ctx.conn
        |> visit(new_path(ctx))
        |> choose_identifiers()

      # Typing is the default.
      assert_has(session, "textarea#script_runner_filter_0_identifiers")

      session
      |> choose_csv()
      |> refute_has("textarea#script_runner_filter_0_identifiers")
      |> assert_has("label", text: "Choose a CSV file")
    end

    test "starts a run against the identifiers in the file", %{tmp_dir: tmp_dir} = ctx do
      device = Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware)
      path = csv(tmp_dir, "devices.csv", "identifier\n#{device.identifier}\n")

      ctx.conn
      |> visit(new_path(ctx))
      |> fill_in("Name", with: "Reboot the listed devices")
      |> fill_in("Script code", with: "Nerves.Runtime.reboot()")
      |> choose_identifiers()
      |> choose_csv()
      |> upload("Choose a CSV file", path)
      |> click_button("Run script")
      |> assert_path(runs_path(ctx))
      |> assert_has("td", text: "Reboot the listed devices")
    end

    test "a CSV with the wrong header is rejected", %{tmp_dir: tmp_dir} = ctx do
      path = csv(tmp_dir, "bad_header.csv", "device_id\nsome-device\n")

      ctx.conn
      |> visit(new_path(ctx))
      |> choose_identifiers()
      |> choose_csv()
      |> upload("Choose a CSV file", path)
      |> assert_has("div", text: "CSV must have a single 'identifier' column header")
    end

    test "a CSV with only a header is rejected", %{tmp_dir: tmp_dir} = ctx do
      path = csv(tmp_dir, "empty.csv", "identifier\n")

      ctx.conn
      |> visit(new_path(ctx))
      |> choose_identifiers()
      |> choose_csv()
      |> upload("Choose a CSV file", path)
      |> assert_has("div", text: "CSV contained no identifier values")
    end

    # A flash is stored in the session cookie, which browsers cap at 4KB, so the
    # unmatched identifiers cannot all go in it.
    test "unmatched identifiers are counted rather than all named", %{tmp_dir: tmp_dir} = ctx do
      device = Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware)
      ghosts = Enum.map_join(1..50, "\n", &"ghost-device-#{&1}")
      path = csv(tmp_dir, "mostly_ghosts.csv", "identifier\n#{device.identifier}\n#{ghosts}\n")

      session =
        ctx.conn
        |> visit(new_path(ctx))
        |> fill_in("Name", with: "Mostly ghosts")
        |> fill_in("Script code", with: "IO.puts(:hi)")
        |> choose_identifiers()
        |> choose_csv()
        |> upload("Choose a CSV file", path)
        |> click_button("Run script")
        |> assert_has("div", text: "50 identifiers matched no device")
        |> assert_has("div", text: "and 40 more")

      # The 41st onwards are counted, not listed.
      refute_has(session, "div", text: "ghost-device-50")
    end
  end

  describe "the run page" do
    defp run_path(ctx, run), do: "#{runs_path(ctx)}/#{run.id}"

    test "a run's row links to its page", ctx do
      run = create_run(ctx, name: "Reboot everything")

      ctx.conn
      |> visit(runs_path(ctx))
      |> click_link("Reboot everything")
      |> assert_path(run_path(ctx, run))
      |> assert_has("h1", text: "Reboot everything")
    end

    test "shows the name, the code and the filter choice", ctx do
      run = create_run(ctx, name: "Reboot the cellular fleet", text: "Nerves.Runtime.reboot()", tag: "cellular")

      ctx.conn
      |> visit(run_path(ctx, run))
      |> assert_has("h1", text: "Reboot the cellular fleet")
      |> assert_has("pre", text: "Nerves.Runtime.reboot()")
      |> assert_has("span", text: "Tags")
      |> assert_has("span", text: "cellular")
      |> assert_has("span", text: "Allow any")
    end

    test "shows how the identifier filter chose its devices", ctx do
      device = Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware)

      {:ok, run, _unmatched} =
        ScriptRunners.create(ctx.product, ctx.user, %{
          name: "By identifier",
          text: "IO.puts(:hi)",
          filter_type: :identifiers,
          filter: %{identifiers: [device.identifier]}
        })

      ctx.conn
      |> visit(run_path(ctx, run))
      |> assert_has("span", text: "Device identifiers")
      |> assert_has("span", text: "1 named")
    end

    test "lists the run's devices", ctx do
      run = create_run(ctx, devices: 3)

      session = visit(ctx.conn, run_path(ctx, run))

      for result <- ScriptRunners.device_results(run) do
        assert_has(session, "td", text: result.device.identifier)
      end
    end

    test "searching narrows the devices to a matching identifier", ctx do
      run = create_run(ctx, tag: "searchable", devices: 2)
      [first, second] = ScriptRunners.device_results(run)

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      filtered = render_change(view, "update-filters", %{"identifier" => first.device.identifier})

      assert filtered =~ first.device.identifier
      refute filtered =~ second.device.identifier
    end

    test "a search matching no device says so", ctx do
      run = create_run(ctx, [])

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      assert render_change(view, "update-filters", %{"identifier" => "nothing-matches-this"}) =~
               "No devices match the current filters."
    end

    test "the device count follows the filters", ctx do
      run = create_run(ctx, tag: "counted", devices: 3)
      [first | _rest] = ScriptRunners.device_results(run)

      1 = ScriptRunners.record_device_result(run.id, first.device_id, :completed, ":ok")

      # The run's own counter is deliberately set to something the rows do not add
      # up to, so a count taken from it rather than from the query is caught.
      {:ok, _run} = Repo.update(Ecto.Changeset.change(run, device_count: 99))

      {:ok, view, html} = live(ctx.conn, run_path(ctx, run))

      # All three rows, not the run's 99.
      assert devices_header(html) =~ "3"
      refute devices_header(html) =~ "99"

      # One of them is completed, so the count follows the filter.
      filtered = render_change(view, "update-filters", %{"status" => "completed"})

      assert devices_header(filtered) =~ "1"
    end

    test "the progress count shows what has an outcome over the total", ctx do
      run = create_run(ctx, tag: "progressing", devices: 3)
      [first, second, _third] = ScriptRunners.device_results(run)

      {:ok, view, html} = live(ctx.conn, run_path(ctx, run))

      # Nothing has an outcome yet, but all three are already counted.
      assert progress(html) =~ "0 / 3"

      # A failure is as finished as a success, so both move the count.
      1 = ScriptRunners.record_device_result(run.id, first.device_id, :completed, ":ok")
      1 = ScriptRunners.record_device_result(run.id, second.device_id, :failed, "boom")

      :ok =
        ScriptRunners.broadcast_progress(run.id, :device_finished, %{device_id: first.device_id, status: :completed})

      assert progress(render(view)) =~ "2 / 3"
    end

    test "the progress count reaches the total when every device is done", ctx do
      run = create_run(ctx, tag: "all-done", devices: 2)

      for result <- ScriptRunners.device_results(run) do
        1 = ScriptRunners.record_device_result(run.id, result.device_id, :completed, ":ok")
      end

      {:ok, _view, html} = live(ctx.conn, run_path(ctx, run))

      assert progress(html) =~ "2 / 2"
    end

    test "the status filter offers every status a result can hold", ctx do
      run = create_run(ctx, [])

      session = visit(ctx.conn, run_path(ctx, run))

      for status <- ScriptRunnerDevice.statuses() do
        assert_has(session, "#device_result_status option", text: to_string(status))
      end
    end

    test "filtering by status narrows the devices to that status", ctx do
      run = create_run(ctx, tag: "by-status", devices: 2)
      [first, second] = ScriptRunners.device_results(run)

      1 = ScriptRunners.record_device_result(run.id, first.device_id, :completed, ":ok")
      1 = ScriptRunners.record_device_result(run.id, second.device_id, :failed, "boom")

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      completed = table(render_change(view, "update-filters", %{"status" => "completed"}))

      assert completed =~ first.device.identifier
      refute completed =~ second.device.identifier

      failed = table(render_change(view, "update-filters", %{"status" => "failed"}))

      assert failed =~ second.device.identifier
      refute failed =~ first.device.identifier
    end

    test "the status filter combines with the identifier search", ctx do
      run = create_run(ctx, tag: "combined", devices: 2)
      [first, second] = ScriptRunners.device_results(run)

      1 = ScriptRunners.record_device_result(run.id, first.device_id, :completed, ":ok")
      1 = ScriptRunners.record_device_result(run.id, second.device_id, :failed, "boom")

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      # Both identifiers start "device-", so the search alone matches the pair and
      # only the status can separate them -- which is what makes this a test of the
      # two filters together rather than of the search.
      both = table(render_change(view, "update-filters", %{"identifier" => "device-"}))

      assert both =~ first.device.identifier
      assert both =~ second.device.identifier

      narrowed =
        table(render_change(view, "update-filters", %{"identifier" => "device-", "status" => "completed"}))

      assert narrowed =~ first.device.identifier
      refute narrowed =~ second.device.identifier
    end

    test "the run's finished time arrives without a reload", ctx do
      run = create_run(ctx, tag: "finishing")

      {:ok, view, html} = live(ctx.conn, run_path(ctx, run))

      # Nothing to show until the run is done.
      assert html =~ "Still running"

      # What the dispatcher does on the pass that sees no unfinished devices.
      {:ok, _finished} = ScriptRunners.mark_finished(run)
      :ok = ScriptRunners.broadcast_progress(run.id, :finished)

      updated = render(view)

      refute updated =~ "Still running"
      # `local_datetime/1` renders the timestamp as a `<time>` element.
      assert updated =~ "<time "
      # The header's own status comes from the same reload.
      assert updated =~ "completed"
    end

    # A bookmarked URL outlives the statuses it was written against.
    test "an unrecognised status in the URL is ignored rather than raising", ctx do
      run = create_run(ctx, tag: "stale-bookmark")
      [result] = ScriptRunners.device_results(run)

      session = visit(ctx.conn, "#{run_path(ctx, run)}?status=not-a-status")

      assert_has(session, "td", text: result.device.identifier)
    end

    test "the devices can be sorted by status", ctx do
      run = create_run(ctx, tag: "sortable", devices: 2)
      [first, second] = ScriptRunners.device_results(run)

      # One of each, so the two orderings differ.
      1 = ScriptRunners.record_device_result(run.id, first.device_id, :completed, ":ok")
      1 = ScriptRunners.record_device_result(run.id, second.device_id, :failed, "boom")

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      # Scoped to the table: both statuses also appear in the progress counts
      # above it, which are not what is being ordered.
      ascending = table(render_change(view, "sort", %{"sort" => "status"}))
      assert position(ascending, "completed") < position(ascending, "failed")

      descending = table(render_change(view, "sort", %{"sort" => "status"}))
      assert position(descending, "failed") < position(descending, "completed")
    end

    test "a device's output is revealed by clicking its row", ctx do
      run = create_run(ctx, tag: "with-output")
      [result] = ScriptRunners.device_results(run)
      1 = ScriptRunners.record_device_result(run.id, result.device_id, :completed, "uptime: 3 days")

      {:ok, view, html} = live(ctx.conn, run_path(ctx, run))

      refute html =~ "uptime: 3 days"

      assert render_click(view, "toggle-output", %{"id" => result.id}) =~ "uptime: 3 days"

      # Clicking the open row closes it again.
      refute render_click(view, "toggle-output", %{"id" => result.id}) =~ "uptime: 3 days"
    end

    test "a device with no output says so rather than showing an empty block", ctx do
      run = create_run(ctx, tag: "timed-out")
      [result] = ScriptRunners.device_results(run)
      1 = ScriptRunners.record_device_result(run.id, result.device_id, :timed_out, nil)

      {:ok, view, _html} = live(ctx.conn, run_path(ctx, run))

      assert render_click(view, "toggle-output", %{"id" => result.id}) =~ "Nothing was recorded for this device."
    end

    test "the status counts follow a device reporting in", ctx do
      run = create_run(ctx, tag: "live-counts")
      [result] = ScriptRunners.device_results(run)

      {:ok, view, html} = live(ctx.conn, run_path(ctx, run))

      # Scoped to the progress panel: the statuses also appear in the table's rows.
      assert progress(html) =~ "pending"

      # What the device worker does when a device answers.
      1 = ScriptRunners.record_device_result(run.id, result.device_id, :completed, ":ok")

      :ok =
        ScriptRunners.broadcast_progress(run.id, :device_finished, %{device_id: result.device_id, status: :completed})

      updated = progress(render(view))

      assert updated =~ "completed"
      refute updated =~ "pending"
    end

    test "another product's run is not reachable", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "Somewhere else"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)
      device = Fixtures.device_fixture(ctx.org, other_product, other_firmware, %{tags: ["elsewhere"]})

      {:ok, other_run, []} =
        ScriptRunners.create(other_product, ctx.user, %{
          name: "Not yours",
          text: "IO.puts(:hi)",
          filter_type: :identifiers,
          filter: %{identifiers: [device.identifier]}
        })

      assert_raise Ecto.NoResultsError, fn ->
        visit(ctx.conn, run_path(ctx, other_run))
      end
    end

    defp position(html, text) do
      case :binary.match(html, text) do
        {at, _length} -> at
        :nomatch -> flunk("expected to find #{inspect(text)} in the rendered page")
      end
    end

    # The statuses appear in three places: the progress counts, the status filter's
    # options and the table's rows. An assertion about one has to say which it
    # means. The progress panel ends where the filter form begins.
    defp progress(html) do
      html
      |> region("run-progress")
      |> String.split(~s(id="device-results-filters-form"), parts: 2)
      |> hd()
    end

    defp table(html), do: region(html, "device-results")

    # The count beside the "Devices" heading, up to the filter form beside it.
    defp devices_header(html) do
      html
      |> region("devices-heading")
      |> String.split(~s(id="device-results-filters-form"), parts: 2)
      |> hd()
    end

    defp region(html, id) do
      [_before, within] = String.split(html, ~s(id="#{id}"), parts: 2)
      within
    end
  end
end
