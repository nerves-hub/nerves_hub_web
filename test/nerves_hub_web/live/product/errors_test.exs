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

  defp record(device, reports) do
    info = %DeviceInfo{
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      device_identifier: device.identifier,
      firmware_metadata: %{uuid: "fw-1"}
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

  describe "the list" do
    test "tells you when the extension is off", %{conn: conn, org: org, product: product} do
      {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("span", text: "Error reports aren't enabled for this product.")
    end

    test "says so when there is nothing to show", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("span", text: "No unresolved errors. Huzzah!")
    end

    test "lists a product's errors", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("** (RuntimeError) sensor bus unreachable"), report("** (MatchError) enoent")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("h1", text: "Errors")
      |> assert_has("a", text: "** (RuntimeError) sensor bus unreachable")
      |> assert_has("a", text: "** (MatchError) enoent")
      |> assert_has("div", text: "MyApp.Worker.run/0")
    end

    test "shows the unresolved count in the header", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("one"), report("two")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> assert_has("#error-count", text: "2 unresolved")
    end

    test "filters by status", %{conn: conn, org: org, product: product, device: device, user: user} do
      record(device, [report("still broken"), report("已 fixed")])

      [first | _rest] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(first, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?status=resolved")
      |> assert_has("a", text: first.reason)
      |> refute_has("a", text: "still broken")
    end

    test "searches the reason", %{conn: conn, org: org, product: product, device: device} do
      record(device, [report("alpha failure"), report("beta failure")])

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?search=alpha")
      |> assert_has("a", text: "alpha failure")
      |> refute_has("a", text: "beta failure")
    end
  end

  describe "lifecycle actions" do
    setup %{device: device} do
      record(device, [report("** (RuntimeError) boom")])
      :ok
    end

    test "resolving updates the status and writes an audit log", %{
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
      |> assert_has("div", text: "Error marked as resolved.")

      assert [%ErrorGroup{status: :resolved, resolved_by_id: resolved_by}] = groups(product)
      assert resolved_by == user.id

      assert Enum.any?(AuditLogs.logs_for(product), &(&1.description =~ "as resolved"))
    end

    test "muting updates the status and writes an audit log", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors")
      |> click_button("Mute")
      |> assert_has("div", text: "Error muted.")

      assert [%ErrorGroup{status: :muted}] = groups(product)
      assert Enum.any?(AuditLogs.logs_for(product), &(&1.description =~ "muted error"))
    end

    test "reopening returns it to the queue", %{conn: conn, org: org, product: product, user: user} do
      [group] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(group, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/errors?status=resolved")
      |> click_button("Reopen")
      |> assert_has("div", text: "Error reopened.")

      assert [%ErrorGroup{status: :unresolved}] = groups(product)
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
          "context" => %{"queue" => "uploads"}
        })
      ])

      %{group: hd(groups(product))}
    end

    test "shows the error, its stacktrace and its devices", %{
      conn: conn,
      org: org,
      product: product,
      group: group,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      # The heading names the section, matching the list page; the reason is
      # the subject alongside it and the crumb in the breadcrumb above.
      |> assert_has("h1", text: "Errors")
      |> assert_has("a", text: "All Errors")
      |> assert_has("span", text: "** (RuntimeError) boom")
      |> assert_has("div", text: "GenServer MyApp.Worker terminating")
      |> assert_has("span", text: "MyApp.Worker.run/0")
      |> assert_has("a", text: device.identifier)
      |> assert_has("div", text: "Occurrences over time")
    end

    test "resolving from the detail page works", %{conn: conn, org: org, product: product, group: group} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/errors/#{group.id}")
      |> click_button("Resolve")
      |> assert_has("div", text: "Error marked as resolved.")

      assert Repo.get!(ErrorGroup, group.id).status == :resolved
    end

    test "a group from another product is not reachable", %{
      conn: conn,
      org: org,
      product: product,
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

    test "hides the link when the extension is off", %{conn: conn, org: org, product: product} do
      {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> refute_has("a", text: "Errors")
    end
  end
end
