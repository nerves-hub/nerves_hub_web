defmodule NervesHubWeb.Live.DeploymentGroups.Show.WorkflowApprovalTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo

  @definition %{
    "version" => 1,
    "steps" => [
      %{"name" => "Sign-off", "type" => "approval_required", "description" => "Check the canaries look healthy"}
    ]
  }

  setup %{user: user, org_key: org_key, product: product, tmp_dir: tmp_dir} do
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{is_active: true, name: "Workflow Group", user: user})

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: @definition}, user)

    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0", dir: tmp_dir})

    {:ok, {release, _}} =
      ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, user, %{}, broadcast: false)

    %{deployment_group: deployment_group, release: release}
  end

  defp visit_group(conn, org, product, deployment_group) do
    visit(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}")
  end

  test "no banner while the approval step has not been reached", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group
  } do
    conn
    |> visit_group(org, product, deployment_group)
    |> refute_has("button", text: "Approve and continue")
  end

  test "the banner appears once the step is in progress", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    release: release
  } do
    [step, _catch_all] = Workflows.release_steps(release.id)
    _ = Workflows.start_step(step)

    conn
    |> visit_group(org, product, deployment_group)
    |> assert_has("div", text: "Waiting on you: Sign-off")
    |> assert_has("div", text: "Check the canaries look healthy")
    |> assert_has("button", text: "Approve and continue")
  end

  # Steps stored before names were required still have none, and the generated
  # catch_all never does. The banner has to read sensibly for those rather than
  # showing a gap where the name would be.
  test "a step with no name falls back to its type", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: deployment_group,
    release: release
  } do
    [step, _catch_all] = Workflows.release_steps(release.id)

    step
    |> Ecto.Changeset.change(%{name: nil})
    |> Repo.update!()
    |> Workflows.start_step()

    conn
    |> visit_group(org, product, deployment_group)
    |> assert_has("div", text: "Waiting on you: Approval required")
    |> assert_has("button", text: "Approve and continue")
  end

  test "approving records who approved it and clears the banner", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group,
    release: release
  } do
    [step, _catch_all] = Workflows.release_steps(release.id)
    _ = Workflows.start_step(step)

    conn
    |> visit_group(org, product, deployment_group)
    |> click_button("Approve and continue")
    |> assert_has("div", text: "Step approved")
    |> refute_has("button", text: "Approve and continue")

    approved = Repo.reload(step)

    assert approved.approved_by_id == user.id
    assert approved.approved_at
  end

  test "an approved step is left alone on a later visit", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: deployment_group,
    release: release
  } do
    [step, _catch_all] = Workflows.release_steps(release.id)

    step
    |> Workflows.start_step()
    |> Workflows.approve_step(user)

    conn
    |> visit_group(org, product, deployment_group)
    |> refute_has("button", text: "Approve and continue")
  end
end
