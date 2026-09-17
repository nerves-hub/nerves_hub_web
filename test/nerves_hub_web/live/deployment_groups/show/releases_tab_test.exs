defmodule NervesHubWeb.Live.DeploymentGroups.Show.ReleasesTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Mimic

  import Ecto.Query, only: [where: 3]

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup context do
    %{
      org: org,
      product: product,
      deployment_group: deployment_group
    } = context

    conn =
      context.conn
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("div", text: "Release History")

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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> refute_has("div", text: "Show notes")
    |> assert_has("div", text: "Firmware: #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)})")
    |> assert_has("div", text: "Release settings updated")
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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> fill_in("Description", with: "Snoot boops")
    |> fill_in("Notes", with: "All the snoots need some boops")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("div", text: "Snoot boops")
    |> assert_has("div", text: "Show notes")
    |> assert_has("div", text: "All the snoots need some boops")
    |> assert_has("div", text: "Firmware: #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)})")
    |> assert_has("div", text: "Release settings updated")
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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("div", text: "Release settings updated")

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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("h1", text: deployment_group.name)
    |> assert_has("div", text: "Release settings")
    |> fill_in("Description", with: Enum.map_join(1..10, " ", fn _ -> "Snoot boops" end))
    |> fill_in("Notes", with: "All the snoots need some boops")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> submit()
    |> assert_has("div", text: "An error occurred while updating the release settings")
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
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("div", text: "Release settings")
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
      |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
      |> assert_has("h1", text: deployment_group.name)
      |> assert_has("div", text: "Release settings")
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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> within("#release-form", fn session ->
      session
      |> select("Firmware version", option: "#{firmware.version}", exact_option: false)
      |> assert_has("p", text: "The current release already has this firmware and archive")
      |> submit()
    end)
    |> assert_has("div", text: "An error occurred while updating the release settings")

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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
    |> check("Required release")
    |> submit()
    |> assert_has("div", text: "Release settings updated")

    [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)
    assert release.firmware_id == new_firmware.id
    assert release.required
  end

  test "marks and unmarks an existing release as required from its edit modal", %{
    conn: conn,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    conn
    |> refute_has("#release-#{release.id}-required")
    |> click_button("#release-#{release.id}-edit", "Edit")
    |> assert_has("#edit-release-content", text: "This release isn't required.")
    |> click_button("#edit-release-toggle-required", "Mark required")
    |> assert_has("p", text: "Release #{release.number} is now required")
    |> assert_has("#release-#{release.id}-required", text: "Required")
    |> assert_has("#edit-release-content", text: "This release is required.")
    |> click_button("#edit-release-toggle-required", "Unmark required")
    |> assert_has("p", text: "Release #{release.number} is no longer required")
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
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> within("#release-form", fn session ->
      session
      |> select("Firmware version", option: "#{new_firmware.version}", exact_option: false)
      |> fill_in("Connecting code", with: ~s/IO.puts("hello")/)
      |> select("Run order", option: "Before the deployment group's code")
      |> submit()
    end)
    |> assert_has("div", text: "Release settings updated")

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
    |> click_button("#release-#{release.id}-edit", "Edit")
    |> refute_has("#edit-release-remove-connecting-code")
    |> within("#connecting-code-form", fn session ->
      session
      |> fill_in("Connecting code", with: "dbg(:hello)")
      |> select("Run order", option: "Override the deployment group's code")
      |> submit()
    end)
    |> assert_has("p", text: "Connecting code for release #{release.number} saved")
    |> assert_has("#release-#{release.id}-connecting-code", text: "Overrides the group's code")

    release = Repo.reload(release)
    assert release.connecting_code == "dbg(:hello)"
    assert release.connecting_code_mode == :override
  end

  test "removes a release's connecting code from its edit modal", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group
  } do
    [release] = ManagedDeployments.list_deployment_releases(deployment_group)

    {:ok, release} =
      ManagedDeployments.update_deployment_release_connecting_code(release, %{"connecting_code" => "dbg(:hello)"}, user)

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}-connecting-code", text: "Runs after the group's code")
    |> click_button("#release-#{release.id}-edit", "Edit")
    |> click_button("#edit-release-remove-connecting-code", "Remove connecting code")
    |> assert_has("p", text: "Connecting code removed from release #{release.number}")
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
    |> assert_has("div", text: "Release History")
    |> refute_has("#release-#{release.id}-edit")
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
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    {:ok, {release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{})

    # A device on the older firmware is what makes the release need a delta
    _ = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
    _ = Fixtures.firmware_delta_fixture(firmware, next_firmware, %{status: :failed})

    conn
    |> visit(~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/releases")
    |> assert_has("#release-#{release.id}-deltas", text: "1")
    |> assert_has("div", text: "(1 failed)")
    |> click_link("#release-#{release.id}-deltas", "1")
    |> assert_has("td", text: firmware.version)
    |> assert_has("div", text: "Failed")
    |> click_link("Retry")
    |> assert_has("p", text: "Building the delta from #{firmware.version} again")
    |> assert_has("div", text: "Processing")

    assert [%{status: :processing}] = ManagedDeployments.release_deltas(Repo.reload(release))
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
      |> assert_has("#release-#{release.id}-deltas", text: "2")
      |> assert_has("div", text: "(1 failed)")

    # The release is already `:failed`, so this leaves its status alone and
    # `release/delta_status` stays quiet -- the count still has to move
    {:ok, second} = second |> Ecto.Changeset.change(status: :failed) |> Repo.update()
    {:ok, _} = ManagedDeployments.recalculate_release_delta_statuses(deployment_group)
    :ok = Firmwares.PubSub.broadcast_delta_status(second)

    # The delta topic delivers asynchronously, so give the LiveView a moment to
    # take the message rather than racing it under a loaded suite
    assert_has(session, "div", text: "(2 failed)", timeout: 1000)
  end

  test "shows created releases", %{conn: conn} do
    assert_has(conn, "div", text: "Firmware: 1.0.0")
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
    {:ok, _} = Firmwares.delete_firmware(old_firmware, user)

    conn
    |> visit("/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/releases")
    # The history still names it, and still links to it...
    |> assert_has("div", text: "Firmware: #{old_firmware.version}")
    |> assert_has("a", text: String.slice(old_firmware.uuid, 0..7))
    # ...but says the firmware itself is gone.
    |> assert_has("span", text: "Deleted")
  end
end
