defmodule NervesHub.AuditLogs.DeploymentGroupTemplatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Fixtures.standard_fixture(tmp_dir)
  end

  defp latest(deployment_group), do: deployment_group |> AuditLogs.logs_for() |> hd()

  test "names a user without putting \"User\" in front", %{user: user, deployment_group: group} do
    :ok = DeploymentGroupTemplates.audit_deployment_updated(user, group)

    log = latest(group)

    assert log.description == "#{user.name} updated deployment group #{group.name}"
    assert log.template == "%{actor} updated deployment group %{resource}"
  end

  test "keeps a step's name as a value, since a workflow file sets it", %{user: user, deployment_group: group} do
    step = %DeploymentWorkflowStep{number: 1, name: "%{actor} <b>Sign-off</b>"}

    :ok = DeploymentGroupTemplates.audit_workflow_step_action(user, group, step, :approved, "Slack user U0ALICE")

    log = latest(group)

    assert log.description ==
             "#{user.name} approved workflow step 1 (%{actor} <b>Sign-off</b>) for deployment group #{group.name} from Slack user U0ALICE"

    assert log.template_values["label"] == "%{actor} <b>Sign-off</b>"
  end

  test "names the device that no longer matches", %{device: device, deployment_group: group} do
    :ok = DeploymentGroupTemplates.audit_deployment_mismatch(device, group, "mismatched version")

    log = latest(group)

    assert log.description ==
             "Device #{device.identifier} no longer matches deployment group #{group.name}'s requirements because of mismatched version"

    assert log.template_values["actor"] == %{"type" => "device", "id" => device.id, "name" => device.identifier}
  end
end
