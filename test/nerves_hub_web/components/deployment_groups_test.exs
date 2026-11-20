defmodule NervesHubWeb.Components.DeploymentGroupsTest do
  use ExUnit.Case, async: true

  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHubWeb.Components.DeploymentGroups

  describe "step_detail/1" do
    test "keeps the case of the tags it names" do
      step = %DeploymentWorkflowStep{
        type: :update_devices,
        matching_conditions: %DeploymentWorkflowStep.Conditions{tags: ["LTE", "Gothenburg-A"], match_limit: 5}
      }

      assert DeploymentGroups.step_detail(step) == "Tagged LTE, Gothenburg-A, up to 5 devices"
    end

    test "starts with a capital when it only limits the count" do
      step = %DeploymentWorkflowStep{
        type: :update_devices,
        matching_conditions: %DeploymentWorkflowStep.Conditions{tags: [], match_limit: 1}
      }

      assert DeploymentGroups.step_detail(step) == "Up to 1 device"
    end
  end

  describe "step_bars/1" do
    import Phoenix.Component, only: [sigil_H: 2]
    import Phoenix.LiveViewTest

    test "keeps a step's failed count whole, so a narrow column moves it under the progress" do
      step = %DeploymentWorkflowStep{
        id: 1,
        number: 1,
        name: "Gothenburg sites",
        type: :update_devices,
        status: :in_progress
      }

      assigns = %{steps: [step], step_counts: %{1 => %{devices: 565, updated: 560, failed: 2}}}

      html = rendered_to_string(~H|<DeploymentGroups.step_bars steps={@steps} step_counts={@step_counts} />|)
      progress = html |> LazyHTML.from_fragment() |> LazyHTML.query("span.flex-wrap > span")

      assert Enum.map(progress, &LazyHTML.text/1) == ["560/565", "· 2 failed"]
    end
  end

  describe "upcase_first/1" do
    test "capitalizes only the first letter" do
      assert DeploymentGroups.upcase_first("tagged LTE") == "Tagged LTE"
      assert DeploymentGroups.upcase_first("") == ""
    end
  end
end
