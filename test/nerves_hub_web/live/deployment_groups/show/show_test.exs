defmodule NervesHubWeb.Live.DeploymentGroups.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.Fixtures
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup %{
          conn: conn,
          user: user,
          org: org,
          product: product,
          org_key: org_key,
          tmp_dir: tmp_dir
        } = context do
    firmware =
      Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{
        is_active: true,
        name: "ShowTest Deployment",
        conditions: %{"version" => "<= 1.0.0", "tags" => ["beta"], "tag_operator" => "or"},
        user: user
      })

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("h1", text: deployment_group.name)

    Map.merge(context, %{
      conn: conn,
      firmware: firmware,
      deployment_group: deployment_group
    })
  end

  test "handle_info :update_inflight_updates while on summary tab", %{conn: conn} do
    conn
    |> unwrap(fn view ->
      send(view.pid, :update_inflight_updates)
      render(view)
    end)
    |> assert_has("h1", exact: false)
  end

  test "a refresh of the summary tab looks up each count once", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1_000)

    queries = count_queries(conn.view.pid)

    send(conn.view.pid, :update_inflight_updates)

    # The refresh ends with the penalty box count, so once that has run, every
    # lookup the refresh makes has run.
    queries = wait_for_query(queries, "updates_blocked_until")

    # One for the list of inflight updates, and one for `Deployments.updating_count/1`
    assert Enum.count(queries, &String.contains?(&1, ~s|FROM "inflight_updates"|)) == 2
  end

  test "opening the summary tab looks up its deltas and stats once", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    queries = count_queries()

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1_000)

    # The page renders once without a socket and again once connected
    assert queries.(["firmware_deltas", "update_stats"]) == %{"firmware_deltas" => 2, "update_stats" => 2}
  end

  test "handle_info :update_inflight_updates on non-summary tab does not crash", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/settings")
    |> unwrap(fn view ->
      send(view.pid, :update_inflight_updates)
      render(view)
    end)
  end

  test "move-matched-devices exit path shows flash error", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _ -> :ok end)

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      raise "simulated async exit"
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "There was an issue moving devices to #{deployment_group.name}",
      timeout: 1000
    )
  end

  test "move-matched-devices success path shows count in flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      %{updated: 1, ignored: 0}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "1 devices moved to #{deployment_group.name}",
      timeout: 1000
    )
  end

  test "move-matched-devices partial success shows partial error flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _, _ -> :ok end)

    expect(BulkActions, :move_many_to_deployment_group, fn _, _, _ ->
      %{updated: 0, ignored: 1}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1000)
    |> click_button("Move device")
    |> assert_has("div",
      text: "couldn't move 1 devices",
      exact: false,
      timeout: 1000
    )
  end

  test "remove-unmatched-devices success path shows count in flash", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Deployments, :remove_unmatched_devices_from_deployment_group, fn _, _ ->
      {:ok, %{updated: 1}}
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
  end

  test "remove-unmatched-devices keeps matching devices without reporting them as failures", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    kept_one = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})
    kept_two = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], deployment_id: deployment_group.id})
    removed = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"], deployment_id: deployment_group.id})

    reject(Logging, :log_to_sentry, 3)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
    |> refute_has("div", text: "couldn't remove", exact: false)

    assert Repo.reload(kept_one).deployment_id == deployment_group.id
    assert Repo.reload(kept_two).deployment_id == deployment_group.id
    refute Repo.reload(removed).deployment_id
  end

  test "remove-unmatched-devices works out which devices to keep off the page's process", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"], deployment_id: deployment_group.id})
    test_pid = self()

    stub(ManagedDeployments, :matched_device_ids, fn group, opts ->
      send(test_pid, {:matching_in, self()})
      call_original(ManagedDeployments, :matched_device_ids, [group, opts])
    end)

    conn =
      visit(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")

    render_click(conn.view, "remove-unmatched-devices-from-deployment-group", %{})

    assert_receive {:matching_in, pid}, 1_000
    refute pid == conn.view.pid
  end

  test "remove-unmatched-devices exit path shows flash error", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    stub(Logging, :log_to_sentry, fn _, _ -> :ok end)

    stub(Deployments, :remove_unmatched_devices_from_deployment_group, fn _, _ ->
      raise "simulated async exit"
    end)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
    |> unwrap(fn view ->
      render_click(view, "remove-unmatched-devices-from-deployment-group", %{})
    end)
    |> assert_has("div",
      text: "There was an issue removing devices from #{deployment_group.name}",
      timeout: 1000
    )
  end

  describe "a user who can only view" do
    setup %{org: org, user: user} do
      {1, _} =
        OrgUser
        |> where([ou], ou.org_id == ^org.id and ou.user_id == ^user.id)
        |> Repo.update_all(set: [role: :view])

      :ok
    end

    test "cannot move matching devices into the deployment group", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
        |> assert_has("span", text: "match outside of deployment group", exact: false, timeout: 1_000)
        |> refute_has("button", text: "Move device")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "move-matched-devices-to-deployment-group", %{}))

      refute Repo.reload(device).deployment_id
    end

    test "cannot remove unmatched devices from the deployment group", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"], deployment_id: deployment_group.id})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
        |> assert_has("span", text: "match inside deployment group", exact: false, timeout: 1_000)
        |> refute_has("button", text: "Remove device")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "remove-unmatched-devices-from-deployment-group", %{}))

      assert Repo.reload(device).deployment_id == deployment_group.id
    end

    test "cannot import devices from a CSV", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
      |> assert_has("div", text: "Device Matching Conditions")
      |> refute_has("label", text: "Import from CSV")
    end
  end

  # Counts the queries a process runs from here on, by the table they read.
  # `nil` counts every process's, which is only safe in a test that isn't async.
  defp count_queries(pid \\ nil) do
    test_pid = self()
    handler_id = "show-test-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:nerves_hub, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if is_nil(pid) or self() == pid, do: send(test_pid, {:query, handler_id, query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    # Gathers what has arrived so far. Given tables, counts the queries naming
    # each, and given `:all`, returns the queries themselves.
    fn
      :all ->
        handler_id |> collect_queries([]) |> Enum.reverse()

      tables ->
        queries = collect_queries(handler_id, [])
        Map.new(tables, fn table -> {table, Enum.count(queries, &String.contains?(&1, ~s|FROM "#{table}"|))} end)
    end
  end

  # Gathers queries as they arrive until one contains `text`
  defp wait_for_query(queries, text, waited \\ 0) do
    seen = queries.(:all)

    cond do
      Enum.any?(seen, &String.contains?(&1, text)) -> seen
      waited >= 1_000 -> flunk("no query containing #{inspect(text)} within 1s")
      true -> Process.sleep(10) && seen ++ wait_for_query(queries, text, waited + 10)
    end
  end

  defp collect_queries(handler_id, acc) do
    receive do
      {:query, ^handler_id, query} -> collect_queries(handler_id, [query | acc])
    after
      0 -> acc
    end
  end
end
