defmodule NervesHub.ManagedDeployments.DeploymentGroupFilteringTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentGroupFiltering
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Repo

  # Build a base query with all three named bindings expected by DeploymentGroupFiltering.
  # Mirrors the query built in ManagedDeployments.filter/2 — the private join_counts helper
  # is reproduced here since it's not part of the public API.
  defp base_query() do
    device_count_subquery =
      Device
      |> select([d], %{device_count: count()})
      |> Repo.exclude_deleted()
      |> where([d], d.deployment_id == parent_as(:deployment_group).id)

    releases_count_subquery =
      DeploymentRelease
      |> select([d], %{releases_count: count()})
      |> where([d], d.deployment_group_id == parent_as(:deployment_group).id)

    DeploymentGroup
    |> from(as: :deployment_group)
    |> join(:left_lateral, [deployment_group: _d], dev in subquery(device_count_subquery),
      as: :device_count,
      on: true
    )
    |> join(:left_lateral, [deployment_group: _d], rel in subquery(releases_count_subquery),
      as: :releases_count,
      on: true
    )
    |> select_merge([device_count: dc, releases_count: rc], %{
      device_count: dc.device_count,
      releases_count: rc.releases_count
    })
    |> ManagedDeployments.join_current_release(true)
  end

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware_arm =
      Fixtures.firmware_fixture(org_key, product, %{
        dir: tmp_dir,
        platform: "rpi0",
        architecture: "arm",
        version: "1.0.0"
      })

    firmware_x86 =
      Fixtures.firmware_fixture(org_key, product, %{
        dir: tmp_dir,
        platform: "x86_board",
        architecture: "x86_64",
        version: "2.0.0"
      })

    group_arm =
      Fixtures.deployment_group_fixture(firmware_arm, %{
        name: "arm-group",
        user: user
      })

    group_x86 =
      Fixtures.deployment_group_fixture(firmware_x86, %{
        name: "x86-group",
        user: user
      })

    %{
      product: product,
      firmware_arm: firmware_arm,
      firmware_x86: firmware_x86,
      group_arm: group_arm,
      group_x86: group_x86
    }
  end

  describe "filter/4 — empty value" do
    test "returns query unchanged for empty string value" do
      query = base_query()
      result = DeploymentGroupFiltering.filter(query, %{}, :name, "")

      # Query object should be structurally identical
      assert result == query
    end

    test "returns query unchanged for unknown key" do
      query = base_query()
      result = DeploymentGroupFiltering.filter(query, %{}, :unknown_field, "some value")

      assert result == query
    end
  end

  describe "filter/4 — :name" do
    test "returns groups matching name substring", %{
      product: product,
      group_arm: group_arm,
      group_x86: group_x86
    } do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :name, "arm")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_arm.id in ids
      refute group_x86.id in ids
    end

    test "is case-insensitive", %{product: product, group_x86: group_x86} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :name, "X86")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_x86.id in ids
    end
  end

  describe "filter/4 — :platform" do
    test "returns only groups with matching firmware platform", %{
      product: product,
      group_arm: group_arm,
      group_x86: group_x86
    } do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :platform, "rpi0")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_arm.id in ids
      refute group_x86.id in ids
    end
  end

  describe "filter/4 — :architecture" do
    test "returns only groups with matching firmware architecture", %{
      product: product,
      group_arm: group_arm,
      group_x86: group_x86
    } do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :architecture, "x86_64")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_x86.id in ids
      refute group_arm.id in ids
    end
  end

  describe "filter/4 — :search" do
    test "matches by name substring", %{product: product, group_arm: group_arm} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :search, "arm-group")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_arm.id in ids
    end

    test "matches by firmware platform", %{
      product: product,
      group_x86: group_x86,
      group_arm: group_arm
    } do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :search, "x86_board")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_x86.id in ids
      refute group_arm.id in ids
    end

    test "matches by firmware architecture", %{product: product, group_arm: group_arm} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :search, "arm")
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_arm.id in ids
    end

    test "empty search string returns query unchanged", %{product: product} do
      all_results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> Repo.all()

      filtered_results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.filter(%{}, :search, "")
        |> Repo.all()

      assert length(filtered_results) == length(all_results)
    end
  end

  describe "build_filters/2" do
    test "applies multiple filters in sequence", %{
      product: product,
      group_arm: group_arm,
      group_x86: group_x86
    } do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.build_filters(%{platform: "rpi0", architecture: "arm"})
        |> Repo.all()

      ids = Enum.map(results, & &1.id)
      assert group_arm.id in ids
      refute group_x86.id in ids
    end

    test "empty filters return all groups", %{product: product} do
      unfiltered_count =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> Repo.aggregate(:count)

      filtered_count =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.build_filters(%{})
        |> Repo.aggregate(:count)

      assert filtered_count == unfiltered_count
    end
  end

  describe "sort/2 — named-binding sorts" do
    test "sorts by :platform ascending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:asc, :platform})
        |> Repo.all()

      platforms =
        Enum.map(results, &get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:platform)]))

      assert platforms == Enum.sort(platforms)
    end

    test "sorts by :platform descending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:desc, :platform})
        |> Repo.all()

      platforms =
        Enum.map(results, &get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:platform)]))

      assert platforms == Enum.sort(platforms, :desc)
    end

    test "sorts by :architecture ascending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:asc, :architecture})
        |> Repo.all()

      archs =
        Enum.map(results, &get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:architecture)]))

      assert archs == Enum.sort(archs)
    end

    test "sorts by :architecture descending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:desc, :architecture})
        |> Repo.all()

      archs =
        Enum.map(results, &get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:architecture)]))

      assert archs == Enum.sort(archs, :desc)
    end

    test "sorts by :device_count ascending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:asc, :device_count})
        |> Repo.all()

      counts = Enum.map(results, & &1.device_count)
      assert counts == Enum.sort(counts)
    end

    test "sorts by :firmware_version ascending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:asc, :firmware_version})
        |> Repo.all()

      versions =
        results
        |> Enum.map(&get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:version)]))
        |> Enum.reject(&is_nil/1)

      assert versions == Enum.sort(versions, &(Version.compare(&1, &2) != :gt))
    end

    test "sorts by :firmware_version descending", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:desc, :firmware_version})
        |> Repo.all()

      versions =
        results
        |> Enum.map(&get_in(&1, [Access.key(:current_release), Access.key(:firmware), Access.key(:version)]))
        |> Enum.reject(&is_nil/1)

      assert versions == Enum.sort(versions, &(Version.compare(&1, &2) != :lt))
    end
  end

  describe "sort/2 — passthrough sort" do
    test "applies direct Ecto sort for {direction, :name}", %{product: product} do
      results =
        base_query()
        |> where([deployment_group: dg], dg.product_id == ^product.id)
        |> DeploymentGroupFiltering.sort({:asc, :name})
        |> Repo.all()

      names = Enum.map(results, & &1.name)
      assert names == Enum.sort(names)
    end
  end
end
