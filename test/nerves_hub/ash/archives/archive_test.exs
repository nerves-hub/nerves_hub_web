defmodule NervesHub.Ash.Archives.ArchiveTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Archives.Archive
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{product: product, archive: archive, firmware: firmware}
  end

  describe "read" do
    test "get by id", %{archive: archive} do
      found = Archive.get!(archive.id)
      assert found.id == archive.id
    end

    test "list_by_product returns archives", %{product: product, archive: archive} do
      archives = Archive.list_by_product!(product.id)
      assert Enum.any?(archives, &(&1.id == archive.id))
    end

    test "get_by_product_and_uuid returns archive", %{product: product, archive: archive} do
      found = Archive.get_by_product_and_uuid!(product.id, archive.uuid)
      assert found.id == archive.id
    end

    test "get_by_product_and_id returns archive", %{product: product, archive: archive} do
      found = Archive.get_by_product_and_id!(product.id, archive.id)
      assert found.id == archive.id
    end
  end

  describe "for_deployment_group" do
    test "returns archive for a deployment group with an archive", %{product: product, archive: archive, firmware: firmware} do
      ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, product.id)

      # Create a deployment group that references the archive
      {:ok, dg} =
        NervesHub.Repo.insert(
          Ecto.Changeset.change(%NervesHub.ManagedDeployments.DeploymentGroup{}, %{
            name: "archive-test-dg",
            org_id: ecto_product.org_id,
            product_id: product.id,
            firmware_id: firmware.id,
            archive_id: archive.id
          })
        )

      result = Archive.for_deployment_group!(dg.id)
      assert result.id == archive.id
    end

    test "returns nil for non-existent deployment group" do
      assert Archive.for_deployment_group!(0) == nil
    end
  end

  describe "destroy" do
    test "soft-deletes archive", %{archive: archive} do
      ash_archive = Archive.get!(archive.id)
      assert :ok = Archive.destroy!(ash_archive)
    end
  end
end
