defmodule NervesHubWeb.Live.DeploymentGroups.Show.OverviewTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Deployments
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup %{
          conn: conn,
          user: user,
          org: org,
          product: product,
          org_key: org_key,
          tmp_dir: tmp_dir,
          fixture: %{firmware: source_firmware}
        } = context do
    target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(target_firmware, %{
        is_active: true,
        name: "Coolest Deployment",
        # The devices these tests add carry one of the tags or the other, so
        # the group matches either.
        conditions: %{"version" => "<= 1.0.0", "tags" => ["beta", "beta-edge"], "tag_operator" => "or"},
        user: user
      })

    device =
      org
      |> Fixtures.device_fixture(product, source_firmware, %{status: :provisioned})
      |> Deployments.update_deployment_group(deployment_group)

    # The device has taken the group's release.
    {:ok, target_metadata} = Firmwares.metadata_from_firmware(target_firmware)
    {:ok, device} = Devices.update_firmware_metadata(device, target_metadata, :unknown, false)

    path = "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}"

    conn =
      conn
      |> visit(path)
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("#deployment-group-overview")

    Map.merge(context, %{
      conn: conn,
      path: path,
      device: device,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware
    })
  end

  test "shows the group's release, firmware and what it matches", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    target_firmware: target_firmware
  } do
    conn
    |> assert_has("#deployment-group-header", text: "Up to date")
    |> assert_has("#deployment-group-header dd", text: target_firmware.version)
    |> assert_has("#deployment-group-header dd", text: "#{target_firmware.platform} · #{target_firmware.architecture}")
    |> assert_has("#deployment-group-header dd", text: "All at once")
    |> assert_has(
      "#deployment-group-header a[href='/org/#{org.name}/#{product.name}/devices?deployment_id=#{deployment_group.id}']",
      text: "1 device"
    )
    |> then(fn session ->
      Enum.reduce(deployment_group.conditions.tags, session, &assert_has(&2, "#deployment-group-header", text: &1))
    end)
    |> assert_has("#rollout", text: "of 1 device is on #{target_firmware.version}")
    |> assert_has("#rollout", text: "No steps. Every device that matches gets the release the next time it connects.")
    |> assert_has("aside", text: "Has any tag")
    |> refute_has("#deployment-group-callout")
  end

  test "a firmware with no size stored still shows", %{conn: conn, path: path, target_firmware: target_firmware} do
    target_firmware |> Ecto.Changeset.change(size: nil) |> Repo.update!()

    conn
    |> visit(path)
    |> assert_has("aside dd a", text: target_firmware.version)
    |> refute_has("aside dd", text: "KB")
  end

  test "names who made the release", %{conn: conn, user: user} do
    assert_has(conn, "aside dd", text: user.name)
  end

  test "names the product API key that made the release", %{
    conn: conn,
    path: path,
    user: user,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    api_key = Fixtures.api_key_fixture(product, user, %{"name" => "CI deploys"})
    new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

    {:ok, _} = ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, api_key, %{})

    conn
    |> visit(path)
    |> assert_has("aside dd", text: "API key CI deploys")
    |> refute_has("aside dd", text: user.name)
  end

  test "the device count leaves out deleted devices", %{
    conn: conn,
    org: org,
    product: product,
    fixture: %{firmware: firmware},
    path: path,
    deployment_group: deployment_group
  } do
    org
    |> Fixtures.device_fixture(product, firmware, %{deleted_at: DateTime.utc_now()})
    |> Deployments.update_deployment_group(deployment_group)

    conn
    |> visit(path)
    |> assert_has("#deployment-group-header a", text: "1 device")
    |> refute_has("#deployment-group-header a", text: "2 devices")
  end

  test "lists the devices the release didn't reach, and why", %{
    conn: conn,
    org: org,
    product: product,
    path: path,
    source_firmware: source_firmware,
    deployment_group: deployment_group
  } do
    conn
    |> assert_has("#unreached", text: "None. Every device in the group has 1.0.0")

    blocked =
      Fixtures.device_fixture(org, product, source_firmware, %{
        deployment_id: deployment_group.id,
        updates_blocked_until: DateTime.add(DateTime.utc_now(), 1, :hour),
        consecutive_failed_updates: 3
      })

    off =
      Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: deployment_group.id, update_mode: :off})

    conn
    |> visit(path)
    |> assert_has("#unreached-#{blocked.id} a", text: blocked.identifier)
    |> assert_has("#unreached-#{blocked.id}", text: "In the penalty box after 3 failures")
    |> assert_has("#unreached-#{off.id}", text: "Updates are turned off on this device")
  end

  describe "devices waiting on a delta that failed" do
    setup %{
      org: org,
      product: product,
      deployment_group: deployment_group,
      source_firmware: source,
      target_firmware: target
    } do
      deployment_group = Repo.update!(Ecto.Changeset.change(deployment_group, delta_updatable: true))
      target = Repo.update!(Ecto.Changeset.change(target, delta_updatable: true))
      Fixtures.firmware_delta_fixture(source, target, %{status: :failed})

      waiting = Fixtures.device_fixture(org, product, source, %{deployment_id: deployment_group.id})

      %{waiting: waiting, deployment_group: deployment_group}
    end

    test "are listed, with the delta's version and both ways to free them", %{
      conn: conn,
      org: org,
      product: product,
      path: path,
      source_firmware: source,
      deployment_group: deployment_group,
      waiting: waiting
    } do
      group_path = "/org/#{org.name}/#{product.name}/deployment_groups/#{URI.encode(deployment_group.name)}"

      conn
      |> visit(path)
      |> assert_has("#unreached-failed-deltas",
        text: "1 device on #{source.version} is waiting on a delta that failed to build."
      )
      |> assert_has("#unreached-failed-deltas a[href='#{group_path}/releases']", text: "Retry it")
      |> assert_has("#unreached-failed-deltas a[href='#{group_path}/settings']", text: "turn delta updates off")
      |> assert_has("#unreached-#{waiting.id}",
        text: "Waiting on the delta from #{source.version}, which failed to build"
      )
    end

    test "aren't held in a group with delta updates off", %{
      conn: conn,
      path: path,
      deployment_group: deployment_group,
      waiting: waiting
    } do
      Repo.update!(Ecto.Changeset.change(deployment_group, delta_updatable: false))

      conn
      |> visit(path)
      |> refute_has("#unreached-failed-deltas")
      |> refute_has("#unreached-#{waiting.id}")
    end

    test "a member who can only manage releases is offered the retry", %{conn: conn, org: org, path: path} do
      role = Fixtures.org_role_fixture(org, %{permissions: ["deployment_group:release:manage"]})
      Repo.update_all(OrgUser, set: [role: nil, org_role_id: role.id])

      conn
      |> visit(path)
      |> assert_has("#unreached-failed-deltas a", text: "Retry it")
      |> assert_has("#unreached-failed-deltas", text: "or have delta updates turned off to send the full firmware")
      |> refute_has("#unreached-failed-deltas a", text: "delta updates")
    end

    test "a member who can only turn delta updates off is offered that", %{conn: conn, org: org, path: path} do
      role = Fixtures.org_role_fixture(org, %{permissions: ["deployment_group:toggle_delta_updates"]})
      Repo.update_all(OrgUser, set: [role: nil, org_role_id: role.id])

      conn
      |> visit(path)
      |> assert_has("#unreached-failed-deltas a", text: "Turn delta updates off")
      |> assert_has("#unreached-failed-deltas", text: "or have it retried on the Releases tab")
      |> refute_has("#unreached-failed-deltas a", text: "Retry")
    end

    test "a member with the view role is told what would free them, with no links", %{conn: conn, path: path} do
      Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit(path)
      |> assert_has("#unreached-failed-deltas",
        text: "The delta can be retried on the Releases tab, or delta updates turned off to send the full firmware."
      )
      |> refute_has("#unreached-failed-deltas a")
    end
  end

  test "activating a release moves the delta subscription to the new firmware", %{
    conn: conn,
    deployment_group: deployment_group,
    target_firmware: target_firmware,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir,
    user: user
  } do
    assert [{live_view, _meta}] = Group.members(NervesHub.Group, "firmware/#{target_firmware.id}")

    other_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.1", dir: tmp_dir})

    {:ok, {_release, _deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, other_firmware, nil, user, %{})

    conn
    |> assert_has("#deployment-group-header dd", text: "2.0.1", timeout: 100)

    assert [{^live_view, _meta}] = Group.members(NervesHub.Group, "firmware/#{other_firmware.id}")
    assert [] == Group.members(NervesHub.Group, "firmware/#{target_firmware.id}")
  end

  test "you can pause and resume the group", %{conn: conn, path: path, deployment_group: deployment_group} do
    conn
    |> click_button("Pause")
    |> assert_has("#pause-group h2", text: "Pause #{deployment_group.name}?")
    |> assert_has("#pause-group p", text: "It stops sending 1.0.0, even to devices that connect, until it’s resumed.")
    |> within("#pause-group", &click_button(&1, "Pause"))
    |> refute_has("#pause-group")
    |> assert_path(path)
    |> assert_has("#deployment-group-callout", text: "This group is paused.")
    |> assert_has("#deployment-group-header", text: "Paused")
    |> then(fn session ->
      {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)
      refute reloaded.is_active

      logs = AuditLogs.logs_for(deployment_group)
      assert Enum.count(logs) == 3
      assert List.first(logs).description =~ ~r/marked deployment/

      session
    end)
    |> click_button("Resume")
    |> assert_has("#resume-group h2", text: "Resume #{deployment_group.name}?")
    |> assert_has("#resume-group p",
      text: "It starts sending 1.0.0 again, though no device in it is waiting for it now."
    )
    |> within("#resume-group", &click_button(&1, "Resume"))
    |> refute_has("#resume-group")
    |> assert_path(path)
    |> refute_has("#deployment-group-callout")
    |> assert_has("button", text: "Pause")
    |> then(fn session ->
      {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)
      assert reloaded.is_active

      logs = AuditLogs.logs_for(reloaded)
      assert Enum.count(logs) == 4
      assert List.first(logs).description =~ ~r/marked deployment/

      session
    end)
  end

  test "cancelling the pause dialog leaves the group running", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> click_button("Pause")
    |> assert_has("#pause-group")
    # Cancel runs the dialog's on_cancel through JS, which pushes this.
    |> unwrap(&render_click(&1, "cancel-confirm", %{}))
    |> refute_has("#pause-group")
    |> assert_has("#deployment-group-header button", text: "Pause")

    {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)
    assert reloaded.is_active
  end

  test "pausing a group someone else already paused changes nothing", %{
    conn: conn,
    user: user,
    deployment_group: deployment_group
  } do
    session = click_button(conn, "Pause")

    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false}, user)
    logs = AuditLogs.logs_for(deployment_group)

    # The pause lands before the page hears of the other one.
    session
    |> unwrap(&render_click(&1, "pause", %{}))
    |> assert_has("div", text: "#{deployment_group.name} is already paused")
    |> refute_has("#pause-group")

    {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)
    refute reloaded.is_active
    assert AuditLogs.logs_for(deployment_group) == logs
  end

  test "the pause dialog closes once the group is paused elsewhere", %{
    conn: conn,
    user: user,
    deployment_group: deployment_group
  } do
    session = click_button(conn, "Pause")

    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{is_active: false}, user)

    session
    |> unwrap(fn view ->
      send(view.pid, :refresh)
      render(view)
    end)
    |> refute_has("#pause-group")
  end

  test "says nothing about matching when every device in the group matches", %{conn: conn} do
    refute_has(conn, "aside", text: "in the group no longer")
  end

  test "removes devices in the group that no longer match", %{
    conn: conn,
    org: org,
    product: product,
    path: path,
    fixture: %{firmware: firmware},
    deployment_group: deployment_group
  } do
    device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id, tags: ["foo"]})

    conn
    |> visit(path)
    |> assert_has("aside p", text: "1 device in the group no longer matches.")
    |> click_button("Remove it")
    |> assert_has("#remove-unmatched-devices h2", text: "Remove 1 device from #{deployment_group.name}?")
    |> within("#remove-unmatched-devices", &click_button(&1, "Remove devices"))
    |> assert_has("div", text: "1 devices removed from #{deployment_group.name}", timeout: 1000)
    |> refute_has("aside", text: "in the group no longer")

    refute Repo.reload(device).deployment_id
  end

  test "moves in matching devices from outside the group", %{
    conn: conn,
    org: org,
    product: product,
    path: path,
    fixture: %{firmware: firmware},
    deployment_group: deployment_group
  } do
    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

    conn
    |> visit(path)
    # The case's own device matches the group too.
    |> assert_has("aside p", text: "2 devices outside the group match.")
    |> click_button("Move them in")
    |> assert_has("#move-devices-in h2", text: "Move 2 devices into #{deployment_group.name}?")
    |> assert_has("#move-devices-in p", text: "Once they’re in, they get its releases, starting with 1.0.0.")
    |> within("#move-devices-in", &click_button(&1, "Move devices"))
    |> assert_has("div", text: "2 devices moved to #{deployment_group.name}", timeout: 1000)
    |> refute_has("aside", text: "outside the group")

    assert Repo.reload(device).deployment_id == deployment_group.id
  end

  test "shows the group's notes and the release's", %{
    conn: conn,
    path: path,
    user: user,
    deployment_group: deployment_group
  } do
    refute_has(conn, "#deployment-group-notes")

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{notes: "Created for the summer campaign hardware batch"},
        user
      )

    deployment_group.current_release
    |> Ecto.Changeset.change(notes: "Fixes the boot loop\nAnd more besides")
    |> Repo.update!()

    conn
    |> visit(path)
    |> assert_has("#deployment-group-notes", text: "Created for the summer campaign hardware batch")
    |> assert_has("aside dd", text: "Fixes the boot loop")
  end

  test "New release opens the Releases tab's form", %{conn: conn, path: path} do
    conn
    |> click_link("New release")
    |> assert_path(URI.encode(path) <> "/releases", query_params: %{"new" => "release"})
    # The modal opens itself when it mounts.
    |> assert_has("#new-release[phx-mounted]")
  end

  describe "CSV import" do
    test "imports devices by identifier from a valid CSV", %{
      conn: conn,
      org: org,
      product: product,
      path: path,
      fixture: %{firmware: firmware},
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"], identifier: "csv-import-device-1"})

      csv_path = Path.join(tmp_dir, "devices.csv")
      :ok = File.write(csv_path, "identifier\ncsv-import-device-1\n")

      conn
      |> visit(path)
      |> upload("Import devices", csv_path)
      |> assert_has("div", text: "imported from CSV", timeout: 1000)
      |> assert_has("#deployment-group-header a", text: "2 devices", timeout: 1000)

      assert Repo.reload(device).deployment_id == deployment_group.id
    end

    test "shows an error for a CSV with the wrong header", %{conn: conn, path: path, tmp_dir: tmp_dir} do
      csv_path = Path.join(tmp_dir, "bad_header.csv")
      :ok = File.write(csv_path, "device_id\nsome-device\n")

      conn
      |> visit(path)
      |> upload("Import devices", csv_path)
      |> assert_has("div", text: "CSV must have a single 'identifier' column header", timeout: 100)
    end

    test "shows an error for an empty CSV (header only)", %{conn: conn, path: path, tmp_dir: tmp_dir} do
      csv_path = Path.join(tmp_dir, "empty.csv")
      :ok = File.write(csv_path, "identifier\n")

      conn
      |> visit(path)
      |> upload("Import devices", csv_path)
      |> assert_has("div", text: "CSV contained no identifier values", timeout: 100)
    end

    test "devices with mismatched platform or architecture are not added", %{
      conn: conn,
      org: org,
      product: product,
      path: path,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      mismatched_firmware =
        Fixtures.firmware_fixture(org_key, product, %{platform: "x86_64", architecture: "amd64", dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, mismatched_firmware, %{identifier: "csv-mismatched-device-1"})

      csv_path = Path.join(tmp_dir, "mismatched.csv")
      :ok = File.write(csv_path, "identifier\ncsv-mismatched-device-1\n")

      conn
      |> visit(path)
      |> upload("Import devices", csv_path)
      |> assert_has("div", text: "0 devices imported from CSV", timeout: 1000)

      refute Repo.reload(device).deployment_id
    end

    test "unknown identifiers add no devices", %{conn: conn, path: path, tmp_dir: tmp_dir} do
      csv_path = Path.join(tmp_dir, "unknown.csv")
      :ok = File.write(csv_path, "identifier\nnonexistent-device-xyz\n")

      conn
      |> visit(path)
      |> upload("Import devices", csv_path)
      |> assert_has("div", text: "0 devices imported from CSV", timeout: 1000)
    end
  end

  describe "a member with the view role" do
    setup %{conn: conn, path: path} do
      Repo.update_all(OrgUser, set: [role: :view])

      %{session: visit(conn, path)}
    end

    test "doesn't see the controls that change the group", %{
      conn: conn,
      org: org,
      product: product,
      path: path,
      fixture: %{firmware: firmware},
      deployment_group: deployment_group
    } do
      Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})
      Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id, tags: ["foo"]})

      conn
      |> visit(path)
      |> assert_has("aside", text: "outside the group match")
      |> assert_has("aside", text: "in the group no longer matches")
      |> refute_has("button", text: "Move them in")
      |> refute_has("button", text: "Remove it")
      |> refute_has("button", text: "Pause")
      |> refute_has("a", text: "New release")
      |> refute_has("#device-csv-form")
    end

    test "can't move matching devices into the group", %{
      session: session,
      org: org,
      product: product,
      fixture: %{firmware: firmware}
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      assert_unauthorized(fn -> render_click(session.view, "move-matched-devices-to-deployment-group", %{}) end)

      refute Repo.reload(device).deployment_id
    end

    test "can't remove unmatched devices from the group", %{
      session: session,
      org: org,
      product: product,
      fixture: %{firmware: firmware},
      deployment_group: deployment_group
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id, tags: ["foo"]})

      assert_unauthorized(fn -> render_click(session.view, "remove-unmatched-devices-from-deployment-group", %{}) end)

      assert Repo.reload(device).deployment_id == deployment_group.id
    end

    test "can't ask to move matching devices in", %{session: session} do
      assert_unauthorized(fn -> render_click(session.view, "ask-move-in", %{}) end)
    end

    test "can't ask to remove unmatched devices", %{session: session} do
      assert_unauthorized(fn -> render_click(session.view, "ask-remove-unmatched", %{}) end)
    end

    test "can't ask to pause the group", %{session: session} do
      assert_unauthorized(fn -> render_click(session.view, "ask-toggle", %{}) end)
    end

    test "can't pause the group", %{session: session, deployment_group: deployment_group} do
      assert_unauthorized(fn -> render_click(session.view, "pause", %{}) end)

      {:ok, reloaded} = ManagedDeployments.get_deployment_group(deployment_group.id)
      assert reloaded.is_active
    end

    test "isn't shown the new release form", %{conn: conn, path: path} do
      conn
      |> visit(path <> "/releases?new=release")
      |> assert_has("#deployment-group-releases")
      |> refute_has("#new-release")
      |> refute_has("#new-release-button")
    end

    test "can't import devices from a CSV", %{session: session} do
      # No upload is configured for a viewer, so LiveView refuses one before
      # any of the file is sent.
      assert_raise RuntimeError, "no uploads allowed for device_csv", fn ->
        file_input(session.view, "#deployment-group-header", :device_csv, [
          %{name: "devices.csv", content: "identifier\nanything\n"}
        ])
      end
    end
  end

  defp assert_unauthorized(fun) do
    Process.flag(:trap_exit, true)

    assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} = catch_exit(fun.())
  end
end
