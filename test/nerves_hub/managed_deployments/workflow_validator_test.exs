defmodule NervesHub.ManagedDeployments.WorkflowValidatorTest do
  use ExUnit.Case, async: true

  alias NervesHub.ManagedDeployments.WorkflowValidator

  defp definition(steps), do: %{"version" => 1, "steps" => steps}

  test "the shipped example definition is valid" do
    definition = "test/fixtures/workflow-definition.json" |> File.read!() |> JSON.decode!()

    assert :ok = WorkflowValidator.validate(definition)
  end

  test "a minimal definition is valid" do
    assert :ok = WorkflowValidator.validate(definition([%{"name" => "Everyone"}]))
  end

  test "version and steps are both required" do
    assert {:error, errors} = WorkflowValidator.validate(%{})

    assert Enum.any?(errors, &(&1 =~ "version"))
    assert Enum.any?(errors, &(&1 =~ "steps"))
  end

  test "a definition needs at least one step" do
    assert {:error, errors} = WorkflowValidator.validate(definition([]))

    assert Enum.any?(errors, &(&1 =~ "steps"))
  end

  describe "step names" do
    test "an update_devices step needs a name" do
      assert {:error, errors} = WorkflowValidator.validate(definition([%{"concurrent_updates" => 5}]))

      assert Enum.any?(errors, &(&1 =~ ~s(steps/0) and &1 =~ "name"))
    end

    # Every step is drawn on the deployment group page, so every step needs
    # something to label it with — including the ones that cover no devices.
    test "so does an approval_required or catch_all step" do
      assert {:error, errors} = WorkflowValidator.validate(definition([%{"type" => "approval_required"}]))
      assert Enum.any?(errors, &(&1 =~ "steps/0" and &1 =~ "name"))

      assert :ok =
               WorkflowValidator.validate(
                 definition([
                   %{"name" => "Canary"},
                   %{"name" => "Sign-off", "type" => "approval_required"},
                   %{"name" => "Everyone else", "type" => "catch_all"}
                 ])
               )
    end
  end

  describe "reporting where the problem is" do
    test "an unknown step type is named along with its position" do
      steps = [%{"name" => "Canary"}, %{"name" => "Wat", "type" => "explode"}]

      assert {:error, errors} = WorkflowValidator.validate(definition(steps))
      assert Enum.any?(errors, &(&1 =~ "steps/1/type"))
    end

    test "a misspelled key is caught rather than silently ignored" do
      steps = [%{"name" => "Canary", "concurrent_update" => 5}]

      assert {:error, errors} = WorkflowValidator.validate(definition(steps))
      assert Enum.any?(errors, &(&1 =~ "concurrent_update"))
    end

    test "a raw interface name is rejected in favour of the humanised one" do
      steps = [%{"name" => "Canary", "matching_conditions" => %{"network_interfaces" => ["wlan0"]}}]

      assert {:error, errors} = WorkflowValidator.validate(definition(steps))
      assert Enum.any?(errors, &(&1 =~ "network_interfaces"))
    end

    test "a match limit of zero is rejected" do
      steps = [%{"name" => "Canary", "matching_conditions" => %{"match_limit" => 0}}]

      assert {:error, errors} = WorkflowValidator.validate(definition(steps))
      assert Enum.any?(errors, &(&1 =~ "match_limit"))
    end

    test "every problem is reported, not just the first" do
      steps = [%{"name" => "Canary", "concurrent_updates" => "ten"}, %{"type" => "nope"}]

      assert {:error, errors} = WorkflowValidator.validate(definition(steps))
      assert length(errors) > 1
    end
  end

  test "something that is not an object is rejected without raising" do
    assert {:error, ["The workflow definition must be a JSON object."]} = WorkflowValidator.validate("nope")
    assert {:error, ["The workflow definition must be a JSON object."]} = WorkflowValidator.validate([1, 2, 3])
  end
end
