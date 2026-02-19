defmodule NervesHub.ManagedDeployments.DeploymentGroupTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  describe "create_changeset/2" do
    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      deployment_group_params = %{
        name: "Bestest Devices",
        conditions: %{
          tags: ["foo"],
          version: "1.2.3"
        },
        firmware_id: firmware.id
      }

      %{deployment_group_params: deployment_group_params, product: product}
    end

    test "conditions are required", %{
      deployment_group_params: deployment_group_params,
      product: product
    } do
      changeset =
        deployment_group_params
        |> Map.put(:conditions, nil)
        |> DeploymentGroup.create_changeset(product)

      refute changeset.valid?
      refute Enum.empty?(errors_on(changeset).conditions)
    end

    test "tags can be empty", %{deployment_group_params: deployment_group_params, product: product} do
      changeset =
        deployment_group_params
        |> Map.put(:conditions, %{"version" => "1.2.0", "tags" => []})
        |> DeploymentGroup.create_changeset(product)

      assert changeset.valid?
    end

    test "version can be an empty string", %{
      deployment_group_params: deployment_group_params,
      product: product
    } do
      changeset =
        deployment_group_params
        |> Map.put(:conditions, %{"version" => "", "tags" => []})
        |> DeploymentGroup.create_changeset(product)

      assert changeset.valid?
    end

    test "a nil version is modified to be blank", %{
      deployment_group_params: deployment_group_params,
      product: product
    } do
      changeset =
        deployment_group_params
        |> Map.put(:conditions, %{version: nil, tags: []})
        |> DeploymentGroup.create_changeset(product)

      assert changeset.valid?
      assert Enum.empty?(changeset.changes.conditions.changes)
    end

    test "version must be a valid Elixir.Version", %{
      deployment_group_params: deployment_group_params,
      product: product
    } do
      changeset =
        deployment_group_params
        |> Map.put(:conditions, %{"version" => "1.2.3.5.6", "tags" => []})
        |> DeploymentGroup.create_changeset(product)

      refute changeset.valid?
      assert errors_on(changeset).conditions.version == ["must be valid Elixir version requirement string"]
    end
  end

  describe "update_changeset/2" do
    setup do
      Fixtures.standard_fixture()
    end

    test "cannot clear conditions", %{deployment_group: deployment_group} do
      changeset = DeploymentGroup.update_changeset(deployment_group, %{conditions: nil})

      refute changeset.valid?
      refute Enum.empty?(errors_on(changeset).conditions)
    end

    test "tags can be cleared", %{deployment_group: deployment_group} do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{conditions: %{"version" => "1.2.0", "tags" => []}})

      assert changeset.valid?
    end

    test "tags can be updated independently of version", %{
      deployment_group: deployment_group
    } do
      changeset = DeploymentGroup.update_changeset(deployment_group, %{conditions: %{"tags" => []}})
      assert changeset.valid?
    end

    test "version can be updated independently of tags", %{deployment_group: deployment_group} do
      changeset = DeploymentGroup.update_changeset(deployment_group, %{conditions: %{"version" => "10.3.4"}})
      assert changeset.valid?
    end

    test "version can be an empty string", %{deployment_group: deployment_group} do
      changeset = DeploymentGroup.update_changeset(deployment_group, %{conditions: %{"version" => "", "tags" => []}})
      assert changeset.valid?
    end

    test "a nil version is modified to be blank", %{deployment_group: deployment_group} do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          conditions: %{version: nil, tags: []}
        })

      assert changeset.valid?
      assert changeset.changes.conditions.changes.version == ""
    end

    test "version must be a valid Elixir.Version", %{deployment_group: deployment_group} do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          conditions: %{"version" => "1.2.3.5.6", "tags" => []}
        })

      refute changeset.valid?
      assert errors_on(changeset.changes.conditions).version == ["must be valid Elixir version requirement string"]
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

    test "firmware cannot be from a different org", %{
      deployment_group: deployment_group
    } do
      new_user = Fixtures.user_fixture(%{email: "user2@test.com"})
      new_org = Fixtures.org_fixture(new_user, %{name: "org2"})
      new_product = Fixtures.product_fixture(new_user, new_org)
      new_org_key = Fixtures.org_key_fixture(new_org, new_user)
      new_firmware = Fixtures.firmware_fixture(new_org_key, new_product)

      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          "firmware_id" => new_firmware.id
        })

      refute changeset.valid?
      assert errors_on(changeset) == %{firmware_id: ["does not exist"]}
    end

    test "archive cannot be from a different org", %{
      deployment_group: deployment_group
    } do
      new_user = Fixtures.user_fixture(%{email: "user2@test.com"})
      new_org = Fixtures.org_fixture(new_user, %{name: "org2"})
      new_product = Fixtures.product_fixture(new_user, new_org)
      new_org_key = Fixtures.org_key_fixture(new_org, new_user)
      new_archive = Fixtures.archive_fixture(new_org_key, new_product)

      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          "archive_id" => new_archive.id
        })

      refute changeset.valid?
      assert errors_on(changeset) == %{archive_id: ["invalid archive"]}
    end
  end

  describe "priority queue validations" do
    setup do
      Fixtures.standard_fixture()
    end

    test "priority_queue_concurrent_updates must be greater than 0", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_concurrent_updates: 0
        })

      refute changeset.valid?
      assert errors_on(changeset).priority_queue_concurrent_updates == ["must be greater than 0"]
    end

    test "priority_queue_concurrent_updates must be greater than 0 (negative)", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_concurrent_updates: -1
        })

      refute changeset.valid?
      assert errors_on(changeset).priority_queue_concurrent_updates == ["must be greater than 0"]
    end

    test "priority_queue_firmware_version_threshold must be valid semantic version", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_firmware_version_threshold: "not-a-version"
        })

      refute changeset.valid?

      assert errors_on(changeset).priority_queue_firmware_version_threshold == [
               "must be a valid semantic version"
             ]
    end

    test "priority_queue_firmware_version_threshold accepts valid semantic versions", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_firmware_version_threshold: "1.2.3"
        })

      assert changeset.valid?
    end

    test "priority_queue_firmware_version_threshold accepts nil", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_firmware_version_threshold: nil
        })

      assert changeset.valid?
    end

    test "priority_queue_firmware_version_threshold accepts empty string", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_firmware_version_threshold: ""
        })

      assert changeset.valid?
    end

    test "priority_queue_enabled can be set", %{deployment_group: deployment_group} do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_enabled: true
        })

      assert changeset.valid?
      assert changeset.changes.priority_queue_enabled == true
    end

    test "all priority queue fields can be updated together", %{
      deployment_group: deployment_group
    } do
      changeset =
        DeploymentGroup.update_changeset(deployment_group, %{
          priority_queue_enabled: true,
          priority_queue_concurrent_updates: 3,
          priority_queue_firmware_version_threshold: "2.0.0"
        })

      assert changeset.valid?
      assert changeset.changes.priority_queue_enabled == true
      assert changeset.changes.priority_queue_concurrent_updates == 3
      assert changeset.changes.priority_queue_firmware_version_threshold == "2.0.0"
    end
  end
end
