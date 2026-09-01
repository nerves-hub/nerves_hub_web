defmodule NervesHub.ManagedDeployments.DeploymentWorkflowStepTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  describe "new_changeset/2" do
    test "an explicit catch_all step keeps its type" do
      changeset = DeploymentWorkflowStep.new_changeset(%{"type" => "catch_all"}, 3)

      assert Changeset.get_field(changeset, :type) == :catch_all
      assert Changeset.get_field(changeset, :number) == 3
    end

    test "an explicit catch_all step can set its own concurrency" do
      changeset = DeploymentWorkflowStep.new_changeset(%{"type" => "catch_all", "concurrent_updates" => 50}, 3)

      assert Changeset.get_field(changeset, :concurrency) == 50
    end

    test "an approval_required step keeps its type" do
      changeset = DeploymentWorkflowStep.new_changeset(%{"type" => "approval_required"}, 2)

      assert Changeset.get_field(changeset, :type) == :approval_required
    end

    test "a step defaults to update_devices" do
      changeset = DeploymentWorkflowStep.new_changeset(%{"name" => "Canary"}, 1)

      assert Changeset.get_field(changeset, :type) == :update_devices
      assert Changeset.get_field(changeset, :name) == "Canary"
      assert Changeset.get_field(changeset, :status) == :waiting
    end

    test "matching conditions are cast into the embed" do
      step = %{
        "name" => "Canary",
        "matching_conditions" => %{
          "tags" => ["canary"],
          "network_interfaces" => ["lan", "wlan"],
          "match_limit" => 20
        }
      }

      conditions = Changeset.get_field(DeploymentWorkflowStep.new_changeset(step, 1), :matching_conditions)

      assert conditions.tags == ["canary"]
      assert conditions.network_interfaces == ["lan", "wlan"]
      assert conditions.match_limit == 20
    end

    test "unknown matching conditions are dropped rather than carried through" do
      step = %{"name" => "Canary", "matching_conditions" => %{"tags" => ["canary"], "nonsense" => "value"}}

      conditions = Changeset.get_field(DeploymentWorkflowStep.new_changeset(step, 1), :matching_conditions)

      assert conditions.tags == ["canary"]
      refute Map.has_key?(conditions, :nonsense)
    end

    # Definitions are uploaded, so an unrecognised type must not reach String.to_atom/1.
    test "an unrecognised type does not create an atom" do
      changeset = DeploymentWorkflowStep.new_changeset(%{"name" => "Canary", "type" => "not_a_real_type"}, 1)

      assert Changeset.get_field(changeset, :type) == :update_devices
      assert_raise ArgumentError, fn -> String.to_existing_atom("not_a_real_type") end
    end
  end
end
