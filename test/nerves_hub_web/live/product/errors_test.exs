defmodule NervesHubWeb.Live.Product.ErrorsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.AuditLogs
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Fixtures
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHubWeb.Live.Product.Errors

  setup context do
    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
    AnalyticsRepo.query("TRUNCATE TABLE device_error_reports", [])

    {:ok, product} =
      Product.changeset(context.product, %{"extensions" => %{"error_reports" => true}})
      |> Repo.update()

    %{context | product: product}
  end

  defp report(reason, overrides \\ %{}) do
    Map.merge(
      %{
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "kind" => "error",
        "reason" => reason,
        "frames" => [%{"module" => "MyApp.Worker", "function" => "run/0", "file" => "w.ex", "line" => 3}]
      },
      overrides
    )
  end

  defp record(device, reports, firmware_uuid \\ "fw-1") do
    info = %DeviceInfo{
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      device_identifier: device.identifier,
      firmware_metadata: %{uuid: firmware_uuid}
    }

    {:ok, _stored} = ErrorReports.record_batch(info, reports)

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
  end

  defp groups(product) do
    Repo.all(from(g in ErrorGroup, where: g.product_id == ^product.id, order_by: g.id))
  end

  defp downgrade_to_view(org, user) do
    {1, _} =
      OrgUser
      |> where([ou], ou.org_id == ^org.id and ou.user_id == ^user.id)
      |> Repo.update_all(set: [role: :view])

    :ok
  end

  # A regressed error keeps the resolve it came back from, which the error
  # page draws as a marker on its chart.
  defp regress(group, user) do
    regressed_at = DateTime.add(DateTime.utc_now(), -1, :day)
    resolved_at = DateTime.add(DateTime.utc_now(), -3, :day)

    {1, _} =
      Repo.update_all(from(g in ErrorGroup, where: g.id == ^group.id),
        set: [regressed_at: regressed_at, resolved_at: resolved_at, resolved_by_id: user.id]
      )

    %{regressed_at: regressed_at, resolved_at: resolved_at}
  end

  describe "the list" do
    test "says error reports are off, and where to turn them on", %{conn: conn, org: org, product: product} do
      {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#errors-off h2", text: "Error reports are off for #{product.name}")
      |> assert_has("#errors-off a", text: "Turn on in Product settings")
      |> assert_has("#errors-off a", text: "Read about error reports")
    end

    test "only offers to turn them on to someone who can", %{conn: conn, org: org, product: product, user: user} do
      {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()
      :ok = downgrade_to_view(org, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#errors-off")
      |> refute_has("a", text: "Turn on in Product settings")
    end

    test "says how devices start reporting before any have", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#errors-none-yet h2", text: "No errors reported yet")
      |> assert_has("#errors-none-yet pre", text: ~s({:nerves_hub_link, "~> 2.13"}))
      |> refute_has("#error-tabs")
    end

    test "lists a product's errors with their top frames", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("** (RuntimeError) sensor bus unreachable"), report("** (MatchError) enoent")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("h1", text: "Errors")
      |> assert_has("a", text: "** (RuntimeError) sensor bus unreachable")
      |> assert_has("a", text: "** (MatchError) enoent")
      |> assert_has("span", text: "MyApp.Worker.run/0 · w.ex:3")
    end

    test "says on the headers which period each count covers", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#errors-events-help [role=tooltip]", text: "since the error was first seen")
      |> assert_has("#errors-devices-help [role=tooltip]", text: "in the last 30 days")
    end

    test "badges an error first seen this week as new", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("[data-badge=new]", text: "new")
    end

    test "counts each status on its tab", %{conn: conn, org: org, product: product, device: device, user: user} do
      record(device, [report("one"), report("two"), report("three")])
      [first | _rest] = groups(product)
      {:ok, _muted} = ErrorReports.mute(first, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#error-tab-unresolved", text: "2")
      |> assert_has("#error-tab-muted", text: "1")
      |> assert_has("#error-tab-resolved", text: "0")
    end

    test "filters by status", %{conn: conn, org: org, product: product, device: device, user: user} do
      record(device, [report("still broken"), report("已 fixed")])

      [first | _rest] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(first, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?status=resolved")
      |> assert_has("a", text: first.reason)
      |> assert_has("span", text: "Resolved by #{user.name}")
      |> refute_has("a", text: "still broken")
    end

    # Every filter value, because reaching these atoms through
    # `String.to_existing_atom/1` used to raise for whichever ones appeared
    # nowhere else as a literal, and which those were depended on what the VM
    # had loaded.
    test "accepts every sort and status the filters offer", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      record(device, [report("boom")])

      for {_label, sort} <- Errors.sort_options(),
          {_label, status} <- Errors.status_options() do
        conn
        |> visit("/org/#{org.name}/#{product.name}/errors?sort=#{sort}&status=#{status}")
        |> assert_has("h1", text: "Errors")
      end
    end

    test "searches the reason", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("alpha failure"), report("beta failure")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?search=alpha")
      |> assert_has("a", text: "alpha failure")
      |> refute_has("a", text: "beta failure")
    end

    test "searches the top frame", %{conn: conn, org: org, product: product, device: device} do
      record(device, [
        report("camera failure", %{"frames" => [%{"module" => "MyApp.Camera", "function" => "capture/1"}]}),
        report("other failure")
      ])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?search=Camera.capture")
      |> assert_has("a", text: "camera failure")
      |> refute_has("a", text: "other failure")
    end

    test "filters by the firmware an error was last seen on", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      record(device, [report("on the known firmware")], firmware.uuid)
      record(device, [report("on some other firmware")], "fw-gone")

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?firmware=#{firmware.version}")
      |> assert_has("a", text: "on the known firmware")
      |> refute_has("a", text: "on some other firmware")
      |> assert_has("#error-filters label", text: "Last seen on")
    end

    test "marks firmware the product no longer has", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")], "0123456789abcdef")

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("span", text: "01234567… deleted")
    end

    test "says where a search's matches are when this tab has none", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      record(device, [report("alpha failure"), report("beta failure")])
      alpha = Enum.find(groups(product), &(&1.reason == "alpha failure"))
      {:ok, _resolved} = ErrorReports.resolve(alpha, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?search=alpha")
      |> assert_has("#errors-no-matches", text: "No unresolved error matches")
      |> assert_has("#errors-no-matches", text: "Matches 1 resolved.")
      |> assert_has("#errors-no-matches a", text: "Clear search")
      |> click_link("Search resolved")
      |> assert_has("a", text: "alpha failure")
    end

    test "says when the last error was resolved once nothing is unresolved", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      record(device, [report("boom")])
      [group] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#errors-tab-empty", text: "Nothing unresolved")
      |> assert_has("#errors-tab-empty", text: "Last error resolved")
    end

    test "explains muting on an empty Muted tab", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?status=muted")
      |> assert_has("#errors-tab-empty", text: "Nothing muted")
      |> assert_has("#errors-tab-empty", text: "never reopens")
    end
  end

  describe "lifecycle actions" do
    setup %{device: device} do
      record(device, [report("** (RuntimeError) boom")])
      :ok
    end

    test "resolving updates the status, writes an audit log and offers an undo", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      # The buttons are icon-only; `sr-only` labels are what name them, both to
      # a screen reader and here.
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> click_button("Resolve")
      |> assert_has("#error-undo", text: "Resolved RuntimeError. It reopens as Regressed if it happens again.")

      assert [%ErrorGroup{status: :resolved, resolved_by_id: resolved_by}] = groups(product)
      assert resolved_by == user.id

      assert Enum.any?(AuditLogs.logs_for(product), &(&1.description =~ "as resolved"))
    end

    test "undoing a resolve puts the error back as it was", %{conn: conn, org: org, product: product, user: user} do
      [group] = groups(product)
      before = regress(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> click_button("Resolve")
      |> click_button("Undo")
      |> refute_has("#error-undo")
      |> assert_has("a", text: "** (RuntimeError) boom")

      assert [%ErrorGroup{status: :unresolved} = restored] = groups(product)
      assert DateTime.compare(restored.regressed_at, before.regressed_at) == :eq
      assert DateTime.compare(restored.resolved_at, before.resolved_at) == :eq
      assert restored.resolved_by_id == user.id
    end

    test "undoing a mute puts the error back as it was", %{conn: conn, org: org, product: product, user: user} do
      [group] = groups(product)
      before = regress(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> click_button("Mute")
      |> click_button("Undo")
      |> refute_has("#error-undo")

      assert [%ErrorGroup{status: :unresolved, muted_at: nil} = restored] = groups(product)
      assert DateTime.compare(restored.regressed_at, before.regressed_at) == :eq
      assert DateTime.compare(restored.resolved_at, before.resolved_at) == :eq
      assert restored.resolved_by_id == user.id
    end

    test "resolving the only error on the last page goes back a page", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # 26 in all, so the 25 a page holds leave one on page 2.
      record(device, Enum.map(1..25, &report("** (RuntimeError) boom #{&1}", %{"fingerprint" => "boom-#{&1}"})))

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?page_number=2")
      |> within("#error-list", fn session -> click_button(session, "Resolve") end)
      |> refute_has("#errors-tab-empty")
      |> assert_has("#error-pager")
      |> assert_has("#error-list a", text: "** (RuntimeError) boom")
    end

    test "undo leaves an error alone once it has come back", %{conn: conn, org: org, product: product} do
      [group] = groups(product)
      regressed_at = DateTime.utc_now()

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/errors")
        |> click_button("Resolve")

      # A device reports it again while the undo is still offered.
      {1, _} =
        Repo.update_all(from(g in ErrorGroup, where: g.id == ^group.id),
          set: [status: :unresolved, regressed_at: regressed_at]
        )

      session
      |> click_button("Undo")
      |> refute_has("#error-undo")
      |> assert_has("div", text: "RuntimeError has changed since, so it was left as it is.")

      assert [%ErrorGroup{status: :unresolved} = kept] = groups(product)
      assert DateTime.compare(kept.regressed_at, regressed_at) == :eq
      refute is_nil(kept.resolved_at)
    end

    test "muting updates the status and writes an audit log", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> click_button("Mute")
      |> assert_has("#error-undo", text: "Muted RuntimeError. It keeps counting and won’t reopen.")

      assert [%ErrorGroup{status: :muted}] = groups(product)
      assert Enum.any?(AuditLogs.logs_for(product), &(&1.description =~ "muted error"))
    end

    test "reopening returns it to the queue", %{conn: conn, org: org, product: product, user: user} do
      [group] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?status=resolved")
      |> click_button("Reopen")
      |> assert_has("div", text: "Error moved back to Unresolved.")

      assert [%ErrorGroup{status: :unresolved, regressed_at: nil}] = groups(product)
    end

    test "a view-only member is not offered the buttons", %{conn: conn, org: org, product: product, user: user} do
      :ok = downgrade_to_view(org, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("a", text: "** (RuntimeError) boom")
      |> refute_has("button", text: "Resolve")
      |> refute_has("button", text: "Mute")
    end
  end

  describe "the detail page" do
    setup %{device: device, product: product} do
      record(device, [
        report("** (RuntimeError) boom", %{
          "message" => "GenServer MyApp.Worker terminating",
          "context" => %{"queue" => "uploads", "uptime_ms" => "11520000"}
        })
      ])

      %{group: hd(groups(product))}
    end

    test "shows the error, its stacktrace, context and devices", %{
      conn: conn,
      org: org,
      product: product,
      group: group,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      # The heading is the error itself, the way the firmware and archive show
      # pages put the thing they are about in the heading. Getting back to the
      # list is the breadcrumb's job.
      |> assert_has("h1", text: "** (RuntimeError) boom")
      |> assert_has("nav a", text: "Errors")
      |> assert_has("nav span", text: "RuntimeError")
      |> assert_has("#error-header-note", text: "First seen")
      |> assert_has("#event-frames li[data-top]", text: "MyApp.Worker.run/0")
      |> assert_has("#event-context", text: "3 h 12 min")
      |> assert_has("#event-context dt", text: "queue")
      |> assert_has("#top-devices a", text: device.identifier)
      |> assert_has("#latest-event a", text: device.identifier)
      |> assert_has("#error-stats", text: "all time")
      |> assert_has("h2", text: "Events per day")
    end

    test "switches the chart to hours", %{conn: conn, org: org, product: product, group: group} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> click_button("24 h")
      |> assert_has("h2", text: "Events per hour")
    end

    # India is UTC+5:30, so its hours start at half past the UTC ones the
    # chart counts in.
    test "counts the hours in a time zone off UTC by half an hour", %{
      conn: conn,
      org: org,
      product: product,
      group: group
    } do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"time_zone" => "Asia/Kolkata"})
        |> live("/org/#{org.name}/#{product.name}/errors/#{group.id}")

      html = view |> element("button", "24 h") |> render_click()

      assert html =~ "Events per hour"
      assert html =~ ~r/<title>[^<]*: 1<\/title>/
    end

    # A device names the firmware each report came from, so there can be any
    # number of them.
    test "lists only the busiest five firmware", %{
      conn: conn,
      org: org,
      product: product,
      group: group,
      device: device
    } do
      record(
        device,
        for(n <- 1..6, do: report("** (RuntimeError) boom", %{"firmware_uuid" => "fw-extra-#{n}"}))
      )

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("#by-firmware li", count: 5)
      |> refute_has("#firmware-tip")
    end

    test "pages through the kept events", %{conn: conn, org: org, product: product, group: group, device: device} do
      record(device, [
        report("** (RuntimeError) boom", %{
          "context" => %{"queue" => "older"},
          "timestamp" => DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_iso8601()
        })
      ])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("#latest-event", text: "1 of 2")
      |> click_button("Older event")
      |> assert_has("#latest-event", text: "2 of 2")
    end

    test "shows the message of a report without frames", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("upstream returned 502", %{"frames" => [], "message" => "payment-gateway: 502"})])
      group = Enum.find(groups(product), &(&1.reason == "upstream returned 502"))

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("#event-message", text: "No stack frames in this report")
      |> assert_has("#event-message pre", text: "payment-gateway: 502")
      |> refute_has("#event-frames")
    end

    test "says a report without frames was sent by hand only when it was", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      record(device, [
        report("upstream returned 502", %{"frames" => [], "source" => "manual", "message" => "payment-gateway: 502"})
      ])

      group = Enum.find(groups(product), &(&1.reason == "upstream returned 502"))

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("#event-message", text: "this report was sent by hand")
    end

    test "says what's gone once every report has aged out", %{conn: conn, org: org, product: product, group: group} do
      AnalyticsRepo.query("TRUNCATE TABLE device_error_reports", [])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("h1", text: "** (RuntimeError) boom")
      |> assert_has("#error-stats", text: "no reports in 30 days")
      |> assert_has("#chart-empty", text: "No reports in the last 30 days")
      |> assert_has("#event-aged-out")
      |> refute_has("#by-firmware")
      |> refute_has("#top-devices")
    end

    test "resolving from the detail page works", %{conn: conn, org: org, product: product, group: group} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> click_button("Resolve")
      |> assert_has("div", text: "Resolved. It reopens as Regressed if it happens again.")
      |> assert_has("#reopen-error")

      assert Repo.get!(ErrorGroup, group.id).status == :resolved
    end

    test "a muted error says it won't reopen and offers Unmute", %{
      conn: conn,
      org: org,
      product: product,
      group: group,
      user: user
    } do
      {:ok, _muted} = ErrorReports.mute(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("#error-header-note", text: "by #{user.name}")
      |> assert_has("#error-header-note", text: "won’t reopen")
      |> click_button("Unmute")
      |> assert_has("div", text: "Unmuted.")

      assert Repo.get!(ErrorGroup, group.id).status == :unresolved
    end

    test "a view-only member gets the page without the buttons", %{
      conn: conn,
      org: org,
      product: product,
      group: group,
      user: user
    } do
      :ok = downgrade_to_view(org, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> assert_has("h1", text: "** (RuntimeError) boom")
      |> refute_has("#resolve-error")
      |> refute_has("#mute-error")
    end

    test "a group from another product is not reachable", %{
      conn: conn,
      org: org,
      user: user,
      group: group
    } do
      other = Fixtures.product_fixture(user, org, %{name: "Another"})

      assert_raise Ecto.NoResultsError, fn ->
        visit(conn, "/org/#{org.name}/#{other.name}/errors/#{group.id}")
      end
    end
  end

  # Deliberately not the devices index: its LiveView starts async queries that
  # outlive the test process, and in a shared sandbox that takes the pool down
  # for whatever runs next. The notifications page renders the same sidebar
  # without any of that.
  describe "the sidebar" do
    test "links to errors when the extension is on", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("a", text: "Errors")
    end

    test "counts the open issues", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("boom")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("#nav-errors", text: "1 open")
      |> assert_has("#product-sidebar[data-attention='alert']")
    end

    test "hides the link when the extension is off", %{conn: conn, org: org, product: product} do
      {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> refute_has("a", text: "Errors")
    end
  end
end
