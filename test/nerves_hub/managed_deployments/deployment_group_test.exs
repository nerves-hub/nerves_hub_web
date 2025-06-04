defmodule NervesHub.ManagedDeployments.DeploymentGroupTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  describe "shared changeset validations" do
    setup do
      deployment_group = %DeploymentGroup{
        org_id: 1,
        firmware_id: 1,
        name: "Bestest Devices",
        conditions: %{
          "tags" => ["foo"],
          "version" => "1.2.3"
        },
        is_active: true,
        product_id: 1,
        concurrent_updates: 1000,
        inflight_update_expiration_minutes: 10
      }

      %{deployment_group: deployment_group, functions: [:create_changeset, :update_changeset]}
    end

    test "cannot clear conditions", %{
      deployment_group: deployment_group,
      functions: functions
    } do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{}
            }
          ])

        refute changeset.valid?
        refute Enum.empty?(errors_on(changeset).conditions)
      end
    end

    test "tags can be cleared", %{deployment_group: deployment_group, functions: functions} do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"version" => "1.2.0", "tags" => []}
            }
          ])

        assert changeset.valid?
      end
    end

    test "tags can be updated independently of version", %{
      deployment_group: deployment_group,
      functions: functions
    } do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"tags" => []}
            }
          ])

        assert changeset.valid?
      end
    end

    test "version can be updated independently of tags", %{
      deployment_group: deployment_group,
      functions: functions
    } do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"version" => "10.3.4"}
            }
          ])

        assert changeset.valid?
      end
    end

    test "version can be an empty string", %{
      deployment_group: deployment_group,
      functions: functions
    } do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"version" => "", "tags" => []}
            }
          ])

        assert changeset.valid?
      end
    end

    test "version cannot be nil", %{deployment_group: deployment_group, functions: functions} do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"version" => nil, "tags" => []}
            }
          ])

        refute changeset.valid?
        assert errors_on(changeset).version == ["can't be blank"]
      end
    end

    test "version must be a valid Elixir.Version", %{
      deployment_group: deployment_group,
      functions: functions
    } do
      for function <- functions do
        changeset =
          apply(DeploymentGroup, function, [
            deployment_group,
            %{
              conditions: %{"version" => "1.2.3.5.6", "tags" => []}
            }
          ])

        refute changeset.valid?
        assert errors_on(changeset).version == ["must be valid Elixir version requirement string"]
      end
    end
  end

  describe "update_changeset/2" do
    setup do
      Fixtures.standard_fixture()
    end

    test "current_updated_devices is reset when firmware changes", %{
      deployment_group: deployment_group,
      org_key: org_key,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product)

      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          "firmware_id" => new_firmware.id
        })

      assert changeset.valid?
      deployment_group = Repo.update!(changeset)
      assert deployment_group.current_updated_devices == 0
    end
  end
end
