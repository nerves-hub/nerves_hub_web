defmodule NervesHubWeb.Live.DeploymentGroups.Show.SettingsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  setup %{conn: conn} = context do
    path =
      "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/settings"

    conn =
      conn
      |> visit(path)
      |> assert_has("#deployment-group-settings")

    context
    |> Map.put(:conn, conn)
    |> Map.put(:path, path)
  end

  defp add_tag(session, tag) do
    unwrap(session, fn view -> view |> element("#settings-matching-tags") |> render_hook("add-tag", %{"tag" => tag}) end)
  end

  defp remove_tag(session, tag), do: click_button(session, "[aria-label='Remove #{tag}']", "")

  test "can update the queue order", %{conn: conn, deployment_group: deployment_group} do
    assert deployment_group.queue_management == :FIFO

    conn
    |> select("Queue order", option: "Connected most recently")
    |> submit()
    |> assert_has("[role=alert]", text: "Sending updates saved")

    assert Repo.reload(deployment_group).queue_management == :LIFO
  end

  test "can update only version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Firmware version", with: "1.2.3")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.version == "1.2.3"
  end

  test "tags are added and removed in the card, and saved with it", %{conn: conn, deployment_group: deployment_group} do
    session =
      conn
      |> assert_has("#settings-matching-form [data-tag]", count: 2)
      |> add_tag("gamma")
      |> remove_tag("beta")
      |> assert_has("#settings-matching-form [data-tag='gamma']")
      |> refute_has("#settings-matching-form [data-tag='beta']")
      |> assert_has("#settings-matching-form input[name='matching[conditions][tags]'][value='beta-edge,gamma']")

    # Nothing is saved until the card is.
    assert Repo.reload(deployment_group).conditions.tags == ["beta", "beta-edge"]

    session
    |> within("#settings-matching-form", &click_button(&1, "Save"))
    |> refute_has("#settings-matching-save")

    assert Repo.reload(deployment_group).conditions.tags == ["beta-edge", "gamma"]
  end

  test "a tag typed but not added is saved with the card", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Tags", with: "gamma")
    |> assert_has("#settings-matching-save")
    |> within("#settings-matching-form", &click_button(&1, "Save"))
    |> assert_has("#settings-matching-form [data-tag='gamma']")
    |> refute_has("#settings-matching-save")

    assert Repo.reload(deployment_group).conditions.tags == ["beta", "beta-edge", "gamma"]
  end

  test "a tag with a space is refused", %{conn: conn} do
    conn
    |> add_tag("two words")
    |> assert_has("#settings-matching-form p", text: "tags cannot contain spaces")
  end

  test "can update tags, how they match, and version together", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> remove_tag("beta")
    |> remove_tag("beta-edge")
    |> add_tag("a")
    |> add_tag("b")
    |> choose("Allow any")
    |> fill_in("Firmware version", with: "1.2.3")
    |> within("#settings-matching-form", &click_button(&1, "Save"))
    |> refute_has("#settings-matching-save")

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.tags == ["a", "b"]
    assert deployment_group.conditions.tag_operator == :or
    assert deployment_group.conditions.version == "1.2.3"

    [user_log, conditions_log | _] = AuditLogs.logs_for(deployment_group)

    assert user_log.description =~ ~r/updated deployment group/
    assert conditions_log.description =~ ~r/conditions changed/
  end

  test "renaming the group moves the page to its new name, and adds an audit log", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> fill_in("Name", with: "Moussaka")
    |> assert_has("#settings-general-save", text: "Links that use the old name stop working.")
    |> within("#settings-general-form", &click_button(&1, "Save"))
    |> assert_path("/org/#{org.name}/#{product.name}/deployment_groups/Moussaka/settings")
    |> assert_has("[role=alert]", text: "General saved")
    |> assert_has("h1", text: "Moussaka")

    assert Repo.reload(deployment_group).name == "Moussaka"

    [audit_log | _] = AuditLogs.logs_for(deployment_group)

    assert audit_log.resource_type == DeploymentGroup
    assert audit_log.description =~ ~r/updated deployment group Moussaka/
  end

  test "a card only saves its own fields", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Name", with: "Not saved")
    |> fill_in("Firmware version", with: "~> 1.0")
    |> within("#settings-matching-form", &click_button(&1, "Save"))
    |> assert_has("#settings-general-save")

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.conditions.version == "~> 1.0"
    refute deployment_group.name == "Not saved"
  end

  test "discarding puts a card back", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Name", with: "Not saved")
    |> within("#settings-general-form", &click_button(&1, "Discard"))
    |> refute_has("#settings-general-save")
    |> assert_has("input[value='#{deployment_group.name}']")
  end

  test "failed update shows errors", %{conn: conn, path: path, deployment_group: deployment_group} do
    conn
    |> fill_in("Firmware version", with: "1.2.3.4.5.6")
    |> within("#settings-matching-form", &click_button(&1, "Save"))
    |> assert_path(path)
    |> assert_has("p", text: "must be valid Elixir version requirement string")

    assert Repo.reload(deployment_group).conditions.version == deployment_group.conditions.version
  end

  test "can clear tags and version", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> remove_tag("beta")
    |> remove_tag("beta-edge")
    |> fill_in("Firmware version", with: "")
    |> submit()

    deployment_group = Repo.reload(deployment_group)

    assert deployment_group.conditions.version == ""
    assert deployment_group.conditions.tags == []
  end

  test "says how many devices a new version requirement sends out of the group", %{
    conn: conn,
    deployment_group: deployment_group,
    device: device
  } do
    _device = Deployments.update_deployment_group(device, deployment_group)

    conn
    |> fill_in("Firmware version", with: "> 2.0.0")
    |> assert_has("#settings-matching-save",
      text: "1 device in the group doesn’t meet > 2.0.0, and leaves it when it next connects."
    )
    |> check("Lock membership")
    |> assert_has("#settings-matching-save", text: "Devices already in the group stay in it.")
  end

  test "can update notes", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("Notes", with: "Created for the summer campaign hardware batch")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.notes == "Created for the summer campaign hardware batch"
  end

  test "can clear notes", %{conn: conn, path: path, deployment_group: deployment_group} do
    conn
    |> fill_in("Notes", with: "some reason")
    |> submit()

    assert Repo.reload(deployment_group).notes == "some reason"

    conn
    |> visit(path)
    |> fill_in("Notes", with: "")
    |> submit()

    assert Repo.reload(deployment_group).notes == nil
  end

  test "can lock and unlock membership", %{conn: conn, path: path, deployment_group: deployment_group} do
    conn
    |> check("Lock membership")
    |> submit()

    assert Repo.reload(deployment_group).lock_device_membership

    conn
    |> visit(path)
    |> uncheck("Lock membership")
    |> submit()

    refute Repo.reload(deployment_group).lock_device_membership
  end

  test "can turn delta updates on", %{conn: conn, deployment_group: deployment_group} do
    refute deployment_group.delta_updatable

    conn
    |> check("Delta updates")
    |> submit()

    assert Repo.reload(deployment_group).delta_updatable
  end

  test "can configure the priority queue", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> check("Priority queue")
    |> fill_in("At once", with: "3")
    |> fill_in("On this version or older", with: "1.2.0")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.priority_queue_enabled
    assert deployment_group.priority_queue_concurrent_updates == 3
    assert deployment_group.priority_queue_firmware_version_threshold == "1.2.0"
  end

  test "an invalid priority queue threshold shows an error", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> check("Priority queue")
    |> fill_in("On this version or older", with: "not-a-version")
    |> submit()
    |> assert_has("p", text: "must be a valid semantic version")

    refute Repo.reload(deployment_group).priority_queue_enabled
  end

  test "can change the penalty box", %{conn: conn, deployment_group: deployment_group} do
    conn
    |> fill_in("After this many failed attempts", with: "4")
    |> fill_in("Or this many close together", with: "6")
    |> fill_in("Within seconds", with: "600")
    |> fill_in("It stays in the penalty box for", with: "60")
    |> submit()

    deployment_group = Repo.reload(deployment_group)
    assert deployment_group.device_failure_threshold == 4
    assert deployment_group.device_failure_rate_amount == 6
    assert deployment_group.device_failure_rate_seconds == 600
    assert deployment_group.penalty_timeout_minutes == 60
  end

  test "a workflow takes over how many devices update at once", %{
    conn: conn,
    path: path,
    user: user,
    deployment_group: deployment_group
  } do
    definition = %{
      "version" => 1,
      "steps" => [
        %{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary", "LTE"], "match_limit" => 5}},
        %{"name" => "Sign-off", "type" => "approval_required"}
      ]
    }

    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: definition}, user)

    conn
    |> visit(path)
    |> assert_has("#workflow-steps li", count: 3)
    |> assert_has("#workflow-steps li", text: "Up to 5 devices tagged canary, LTE")
    |> assert_has("#workflow-steps li", text: "Stops after 1 failure")
    |> assert_has("#workflow-steps li", text: "Remaining devices")
    |> assert_has("fieldset[disabled] #settings-sending_concurrent_updates")
    |> assert_has("fieldset[disabled] #settings-sending_priority_queue_enabled")
  end

  test "a member who can only view sees the settings but can't change them", %{
    conn: conn,
    path: path,
    org: org,
    user: user
  } do
    {:ok, _} = NervesHub.Accounts.change_org_user_role(NervesHub.Accounts.get_org_user!(org, user.id), :view)

    conn
    |> visit(path)
    |> assert_has("#read-only-notice")
    |> assert_has("#settings-general-form fieldset[disabled]")
    |> refute_has("#settings-delete")
    |> refute_has("#upload-workflow")
  end

  test "you can delete a deployment group with no devices attached to it", %{
    conn: conn,
    path: path,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    Repo.delete_all(Device)

    conn
    |> visit(path)
    |> assert_has("#settings-delete", text: "No devices are in it.")
    |> click_button("Delete group")
    |> within("#settings-confirm", &click_button(&1, "Delete #{deployment_group.name}"))
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups"))
    |> assert_has("div", text: "Deployment Group successfully deleted")

    assert ManagedDeployments.get_deployment_group(deployment_group.id) ==
             {:error, :not_found}

    [log | _] = AuditLogs.logs_for(deployment_group)

    assert log.description =~ ~r/deleted deployment/
  end

  test "you can delete a deployment group with devices attached to it", %{
    conn: conn,
    path: path,
    org: org,
    product: product,
    deployment_group: deployment_group,
    device: device
  } do
    device = Deployments.update_deployment_group(device, deployment_group)

    assert Enum.count(Repo.all_by(Device, deployment_id: deployment_group.id)) == 1

    conn
    |> visit(path)
    |> click_button("Delete group")
    |> assert_has("#settings-confirm", text: "Its 1 device leaves it")
    |> within("#settings-confirm", &click_button(&1, "Delete #{deployment_group.name}"))
    |> assert_path(URI.encode("/org/#{org.name}/#{product.name}/deployment_groups"))
    |> assert_has("div", text: "Deployment Group successfully deleted")

    assert ManagedDeployments.get_deployment_group(deployment_group.id) ==
             {:error, :not_found}

    [log | _] = AuditLogs.logs_for(deployment_group)

    assert log.description =~ ~r/deleted deployment/

    device = Repo.reload(device)
    assert device.deployment_id == nil
    assert device.deleted_at == nil
  end
end
