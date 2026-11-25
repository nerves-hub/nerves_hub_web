defmodule NervesHubWeb.Live.DeploymentGroups.Show.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Mimic
  use Oban.Testing, repo: NervesHub.Repo

  import Ecto.Query, only: [where: 3]

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteFirmware
  alias Phoenix.Socket.Broadcast

  setup context do
    %{
      org: org,
      product: product,
      deployment_group: deployment_group
    } = context

    conn =
      context.conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("#deployment-group-releases")

    %{context | conn: conn}
  end

  test "successfully creates a new release", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("#new-release h2", text: "New release for #{deployment_group.name}")
    |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("p", text: "Release 2 created with #{new_firmware.version}")
    |> refute_has("#new-release")
    |> assert_has("#deployment-group-releases", text: "Release 2")
    |> assert_has("#deployment-group-releases a", text: new_firmware.version)
    |> assert_has("#deployment-group-releases", text: String.slice(new_firmware.uuid, 0..7))
  end

  test "says what happens to the one device without the current release", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    old_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
    _ = Fixtures.device_fixture(org, product, old_firmware, %{deployment_id: deployment_group.id})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> assert_has("#new-release-what-happens",
      text: "The 1 device that doesn’t have it will get the new firmware instead."
    )
  end

  test "opens New release from another tab", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/activity")
    |> click_link("#new-release-button", "New release")
    |> assert_path(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases",
      query_params: %{new: "release"}
    )
    |> assert_has("#new-release h2", text: "New release for #{deployment_group.name}")
  end

  test "successfully creates a new release with a description and notes", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> fill_in("Description", with: "Snoot boops")
    |> fill_in("Notes · optional", with: "All the snoots need some boops")
    |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("p", text: "Release 2 created with #{new_firmware.version}")

    [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)

    # The new release is the one left open, notes and all
    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}", text: "Snoot boops")
    |> assert_has("#release-#{release.id}-details", text: "All the snoots need some boops")
  end

  test "audits a new release once", %{
    conn: conn,
    org: org,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    audit_logs_before = AuditLogs.logs_for(deployment_group)

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("p", text: "Release 2 created")

    assert [audit_log] = AuditLogs.logs_for(deployment_group) -- audit_logs_before
    assert audit_log.description =~ "created a new release"
  end

  test "release description can't be longer than 100 characters", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> fill_in("Description", with: Enum.map_join(1..10, " ", fn _ -> "Snoot boops" end))
    |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("#release-form", text: "should be at most 100 character(s)")
    |> assert_has("#new-release")

    assert [_first_release] = ManagedDeployments.list_deployment_releases(deployment_group)
  end

  test "updates the available firmware list when new firmware is uploaded", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases?new=release")
      |> assert_has("option[value=\"#{firmware.id}\"]", text: "#{firmware.version}")

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> assert_has("option[value=\"#{new_firmware.id}\"]", text: "#{new_firmware.version}", timeout: 100)
    |> assert_has("p",
      text: "New firmware #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)}) is available for selection"
    )
  end

  test "updates the available firmware list when a firmware is deleted", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware_1 = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    firmware_2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware_1, %{user: user})

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases?new=release")
      |> assert_has("option[value=\"#{firmware_1.id}\"]", text: "#{firmware_1.version}")
      |> assert_has("option[value=\"#{firmware_2.id}\"]", text: "#{firmware_2.version}")

    Firmwares.delete_firmware(firmware_2)

    conn
    |> assert_has("option[value=\"#{firmware_1.id}\"]", text: "#{firmware_1.version}", timeout: 100)
    |> refute_has("option[value=\"#{firmware_2.id}\"]", text: "#{firmware_2.version}")
    |> assert_has("p",
      text:
        "Firmware list has been updated. Firmware #{firmware_2.version} (#{String.slice(firmware_2.uuid, 0..7)}) has been deleted by another user."
    )
  end

  test "won't create a release with the current release's firmware and archive", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> within("#release-form", fn session ->
      session
      |> select("Firmware", option: "#{firmware.version}", exact_option: false)
      |> assert_has("p", text: "The current release already has this firmware and archive")
      |> submit()
    end)
    |> assert_has("#release-form p", text: "The current release already has this firmware and archive")

    assert [_first_release] = ManagedDeployments.list_deployment_releases(deployment_group)
  end

  test "creates a required release", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
    |> check("Required release")
    |> submit()
    |> assert_has("p", text: "Release 2 created")

    [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)
    assert release.firmware_id == new_firmware.id
    assert release.required
  end

  test "marks and unmarks an existing release as required from its edit dialog", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    conn
    |> refute_has("#release-#{release.id}-required")
    |> click_button("#release-#{release.id}-edit", "Edit release")
    |> assert_has("#edit-release h2", text: "Edit release #{release.number}")
    |> within("#edit-release-form", fn session ->
      session
      |> check("Required release")
      |> submit()
    end)
    |> assert_has("p", text: "Release #{release.number} saved")
    |> refute_has("#edit-release")
    |> assert_has("#release-#{release.id}-required", text: "Required")

    assert Repo.reload(release).required

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> click_button("#release-#{release.id}-edit", "Edit release")
    |> within("#edit-release-form", fn session ->
      session
      |> uncheck("Required release")
      |> submit()
    end)
    |> assert_has("p", text: "Release #{release.number} saved")
    |> refute_has("#release-#{release.id}-required")

    refute Repo.reload(release).required
  end

  test "creates a release with connecting code", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    tmp_dir: tmp_dir
  } do
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases?new=release")
    |> refute_has("#release-form textarea[name='deployment_release[connecting_code]']")
    |> click_button("#release-form button[aria-expanded]", "Connecting code")
    |> within("#release-form", fn session ->
      session
      |> select("Firmware", option: "#{new_firmware.version}", exact_option: false)
      |> fill_in("Connecting code", with: ~s/IO.puts("hello")/)
      |> select("Runs", option: "Before the group’s code")
      |> submit()
    end)
    |> assert_has("p", text: "Release 2 created")

    [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)
    assert release.firmware_id == new_firmware.id
    assert release.connecting_code == ~s/IO.puts("hello")/
    assert release.connecting_code_mode == :first
  end

  test "edits a release's connecting code from the history", %{
    conn: conn,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    conn
    |> refute_has("#release-#{release.id}-connecting-code")
    |> click_button("#release-#{release.id}-edit", "Edit release")
    |> refute_has("#edit-release-remove-connecting-code")
    |> within("#edit-release-form", fn session ->
      session
      |> fill_in("Connecting code", with: "dbg(:hello)")
      |> select("Runs", option: "Instead of the group’s code")
      |> submit()
    end)
    |> assert_has("p", text: "Release #{release.number} saved")
    |> assert_has("#release-#{release.id}-connecting-code", text: "runs instead of the group’s code")

    release = Repo.reload(release)
    assert release.connecting_code == "dbg(:hello)"
    assert release.connecting_code_mode == :override
  end

  test "removes a release's connecting code from its edit dialog", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    {:ok, release} =
      ManagedDeployments.update_deployment_release(release, %{"connecting_code" => "dbg(:hello)"}, user)

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}-connecting-code", text: "runs after the group’s code")
    |> click_button("#release-#{release.id}-edit", "Edit release")
    |> click_button("#edit-release-remove-connecting-code", "Remove connecting code")
    # It only empties the field: nothing changes until the dialog is saved.
    |> assert_has("#edit-release textarea", text: "", exact: true)
    |> assert_has("#edit-release-form_connecting_code-hint",
      text: "Saving removes release #{release.number}’s connecting code. Devices won’t run it when they connect."
    )
    |> refute_has("#edit-release-remove-connecting-code")
    |> then(fn session ->
      assert Repo.reload(release).connecting_code == "dbg(:hello)"
      session
    end)
    |> click_button("Save changes")
    |> assert_has("p", text: "Release #{release.number} saved")
    |> refute_has("#release-#{release.id}-connecting-code")

    assert is_nil(Repo.reload(release).connecting_code)
  end

  test "doesn't offer release actions to a user who can't update the group", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    {1, _} =
      OrgUser
      |> where([ou], ou.org_id == ^org.id and ou.user_id == ^user.id)
      |> Repo.update_all(set: [role: :view])

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}-details")
    |> refute_has("#release-#{release.id}-edit")
    |> refute_has("#new-release-button")
  end

  test "offers release actions by deployment_group:release:manage, not deployment_group:update", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)
    path = ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases"
    org_user = NervesHub.Accounts.get_org_user!(org, user.id)

    settings_only = Fixtures.org_role_fixture(org, %{name: "Settings", permissions: ["deployment_group:update"]})
    {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, settings_only)

    conn
    |> visit(path)
    |> assert_has("#release-#{release.id}-details")
    |> refute_has("#release-#{release.id}-edit")
    |> refute_has("#new-release-button")

    releaser = Fixtures.org_role_fixture(org, %{name: "Releaser", permissions: ["deployment_group:release:manage"]})
    {:ok, _} = NervesHub.Accounts.change_org_user_role(NervesHub.Accounts.get_org_user!(org, user.id), releaser)

    conn
    |> visit(path)
    |> assert_has("#release-#{release.id}-edit")
    |> assert_has("#new-release-button")
  end

  test "shows a release's deltas, and retries a failed one", %{
    conn: conn,
    org: org,
    org_key: org_key,
    product: product,
    user: user,
    firmware: firmware,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    next_firmware =
      org_key
      |> Fixtures.firmware_fixture(product, %{version: "2.0.0", dir: tmp_dir})
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

    {:ok, {release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{})

    # With delta updates on, the devices on the older firmware wait for its delta
    deployment_group = Repo.update!(Ecto.Changeset.change(deployment_group, %{delta_updatable: true}))

    # A device on the older firmware is what makes the release need a delta
    _ = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
    delta = Fixtures.firmware_delta_fixture(firmware, next_firmware, %{status: :failed})
    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

    # The new release is the current one, so it starts open with its deltas
    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}-delta-count", text: "1 delta update")
    |> assert_has("#release-#{release.id}-delta-count .text-alert-content", text: "1 failed")
    |> assert_has("#release-delta-#{delta.id}", text: "From #{firmware.version}")
    |> assert_has("#release-delta-#{delta.id}", text: "Failed")
    |> assert_has("#release-delta-#{delta.id}", text: "wait for a retry")
    |> click_button("#release-delta-#{delta.id} button", "Retry")
    |> assert_has("p", text: "Building the delta from #{firmware.version} again")
    # A retry starts a new delta in place of the failed one
    |> assert_has("#release-#{release.id}-deltas", text: "Building")

    assert [%{status: :processing}] = ManagedDeployments.release_deltas(Repo.reload(release))

    # Straight from failed to preparing. A moment reading as ready is enough for
    # the orchestrator to send full firmware to the devices waiting on the delta.
    assert_received %Broadcast{event: "release/delta_status", payload: %{from: :failed, to: :preparing}}
    refute_received %Broadcast{event: "release/delta_status", payload: %{to: :ready}}
    refute_enqueued(worker: DeleteFirmware)
  end

  test "a failed delta to firmware that can't take one holds no one", %{
    conn: conn,
    org: org,
    org_key: org_key,
    product: product,
    user: user,
    firmware: firmware,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    refute next_firmware.delta_updatable

    {:ok, {_release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{})

    deployment_group = Repo.update!(Ecto.Changeset.change(deployment_group, %{delta_updatable: true}))

    _ = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
    delta = Fixtures.firmware_delta_fixture(firmware, next_firmware, %{status: :failed})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-delta-#{delta.id}", text: "Failed")
    |> assert_has("#release-delta-#{delta.id}", text: "get the full")
    |> refute_has("#release-delta-#{delta.id}", text: "wait for a retry")
  end

  test "deletes a built delta after asking, for every group sending the release", %{
    conn: conn,
    org: org,
    org_key: org_key,
    product: product,
    user: user,
    firmware: firmware,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    {:ok, {release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{})

    _ = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
    delta = Fixtures.firmware_delta_fixture(firmware, next_firmware, %{status: :completed})
    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-delta-#{delta.id}", text: "Ready")
    |> click_button("#release-delta-#{delta.id} button", "Delete")
    |> assert_has("#delete-delta h2", text: "Delete the delta from #{firmware.version}?")
    |> assert_has("#delete-delta-subtitle", text: "#{firmware.version} → #{next_firmware.version}")
    |> assert_has("#delete-delta p",
      text: "Every deployment group sending #{next_firmware.version} shares this delta, so that goes for all of them."
    )
    |> then(fn session ->
      # Nothing is deleted until the dialog's own button is pressed.
      assert [%{id: id}] = ManagedDeployments.release_deltas(Repo.reload(release))
      assert id == delta.id
      session
    end)
    |> within("#delete-delta", &click_button(&1, "Delete delta"))
    |> assert_has("p", text: "Deleted the delta from #{firmware.version}")
    |> refute_has("#delete-delta")
    |> refute_has("#release-delta-#{delta.id}")

    assert [] == ManagedDeployments.release_deltas(Repo.reload(release))
  end

  test "counts a second failure that leaves the release's status where it was", %{
    conn: conn,
    org: org,
    org_key: org_key,
    product: product,
    user: user,
    firmware: firmware,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    other_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.5.0", dir: tmp_dir})
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    {:ok, {release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{})

    # Two devices on different firmware, so the release needs two deltas
    _ = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
    _ = Fixtures.device_fixture(org, product, other_firmware, %{deployment_id: deployment_group.id})

    _ = Fixtures.firmware_delta_fixture(firmware, next_firmware, %{status: :failed})
    second = Fixtures.firmware_delta_fixture(other_firmware, next_firmware, %{status: :completed})

    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)

    session =
      conn
      |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
      |> assert_has("#release-#{release.id}-delta-count", text: "2 delta updates")
      |> assert_has("#release-#{release.id}-delta-count .text-alert-content", text: "1 failed")

    # The release is already `:failed`, so this leaves its status alone and
    # `release/delta_status` stays quiet -- the count still has to move
    {:ok, second} = second |> Ecto.Changeset.change(status: :failed) |> Repo.update()
    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
    :ok = Firmwares.PubSub.broadcast_delta_status(second)

    # The delta topic delivers asynchronously, so give the LiveView a moment to
    # take the message rather than racing it under a loaded suite
    assert_has(session, "#release-#{release.id}-delta-count .text-alert-content", text: "2 failed", timeout: 1000)
  end

  test "shows created releases", %{conn: conn, deployment_group: deployment_group} do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    conn
    |> assert_has("#release-#{release.id}", text: "1.0.0")
    |> assert_has("#release-#{release.id}", text: "Release 1")
    |> assert_has("#release-#{release.id}", text: "Firmware only")
  end

  test "names the product API key that made a release", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    api_key = Fixtures.api_key_fixture(product, user, %{"name" => "CI deploys"})
    new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

    {:ok, _} = ManagedDeployments.create_deployment_release(deployment_group, new_firmware, nil, api_key, %{})

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
    |> assert_has("span", text: "API key CI deploys")
  end

  test "badges a release whose firmware has been deleted", %{
    conn: conn,
    user: user,
    org: org,
    org_key: org_key,
    product: product,
    deployment_group: deployment_group,
    tmp_dir: tmp_dir
  } do
    # Move the group on so the original firmware stops being the current
    # release, which is what makes it deletable at all.
    replacement = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

    {:ok, _} =
      ManagedDeployments.create_deployment_release(deployment_group, replacement, nil, user, %{})

    old_firmware = deployment_group.current_release.firmware
    old_release = deployment_group.current_release
    {:ok, _} = Firmwares.delete_firmware(old_firmware, user)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
    # The history still names it...
    |> assert_has("#release-#{old_release.id}", text: old_firmware.version)
    # ...but says the firmware itself is gone...
    |> assert_has("#release-#{old_release.id}-deleted", text: "Deleted")
    # ...and opening it still links to it.
    |> click_button("#release-#{old_release.id} button[aria-expanded]", "Release #{old_release.number}")
    |> assert_has("#release-#{old_release.id}-details a", text: old_firmware.version)
    |> assert_has("#release-#{old_release.id}-details", text: String.slice(old_firmware.uuid, 0..7))
  end
end
