defmodule NervesHub.ArchivesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Archives
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Support
  alias NervesHub.Workers.DeleteArchive

  describe "archive_for_deployment_group/2" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      {:ok, {_release, deployment_group}} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, archive, user, %{})

      %{deployment_group: deployment_group, firmware: firmware, next_firmware: next_firmware, archive: archive}
    end

    test "goes to a device running the current release's firmware", context do
      %{archive: archive, deployment_group: deployment_group, next_firmware: next_firmware} = context

      assert %{id: archive_id} = Archives.archive_for_deployment_group(deployment_group.id, next_firmware.uuid)
      assert archive_id == archive.id
    end

    # A device on its way through a required release is not on the release the
    # archive belongs to yet, and gets it on the connection after it lands there.
    test "is held back from a device still on older firmware", context do
      %{deployment_group: deployment_group, firmware: firmware} = context

      assert is_nil(Archives.archive_for_deployment_group(deployment_group.id, firmware.uuid))
      assert is_nil(Archives.archive_for_deployment_group(deployment_group.id, nil))
      assert is_nil(Archives.archive_for_deployment_group(nil, firmware.uuid))
    end
  end

  describe "creating archives" do
    test "success: on a product", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture(%{name: "user"})
      org = Fixtures.org_fixture(user, %{name: "user"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org, %{name: "Hop"})

      {:ok, file_path} =
        Support.Archives.create_signed_archive(
          org_key.name,
          "manifest",
          "signed-manifest",
          %{
            platform: "generic",
            architecture: "generic",
            version: "0.1.0",
            dir: tmp_dir
          }
        )

      {:ok, archive} = Archives.create(product, file_path)

      assert archive.org_key_id == org_key.id
      assert archive.platform == "generic"
      assert archive.architecture == "generic"
      assert archive.version == "0.1.0"
      assert archive.uuid
    end

    test "says when the archive needs a newer fwup", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture(%{name: "user"})
      org = Fixtures.org_fixture(user, %{name: "user"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org, %{name: "Hop"})

      {:ok, _} = Support.Fwup.create_firmware(tmp_dir, "manifest")
      {:ok, _} = Support.Fwup.require_newer_fwup(tmp_dir, "manifest", "newer")
      {:ok, file_path} = Support.Fwup.sign_firmware(tmp_dir, org_key.name, "newer", "signed")

      assert {:error, {:fwup_too_old, "99.0.0", _installed}} = Archives.create(product, file_path)
    end

    test "refuses an archive when the org has no fwup keys", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture(%{name: "user"})
      org = Fixtures.org_fixture(user, %{name: "user"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org, %{name: "Hop"})

      {:ok, file_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{dir: tmp_dir})

      NervesHub.Repo.delete!(org_key)

      assert Archives.create(product, file_path) == {:error, :no_public_keys}
    end
  end

  describe "filter/2" do
    test "returns archives with non-default sort", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      {archives, _meta} =
        Archives.filter(product, %{sort: "uuid", sort_direction: "asc"})

      assert Enum.map(archives, & &1.id) == [archive.id]
    end
  end

  describe "delete_archive/1" do
    test "delete archive", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _} = Archives.delete_archive(archive)

      assert_enqueued(
        worker: DeleteArchive,
        args: %{
          "archive_path" => "/archives/#{org.id}/#{product.id}/#{archive.uuid}.fw"
        }
      )

      assert {:error, :not_found} = Archives.get(product, archive.uuid)
    end

    test "refuses an archive that a deployment release uses", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      {:ok, _} =
        ManagedDeployments.create_deployment_release(deployment_group, firmware, archive, user, %{})

      assert {:error, %Ecto.Changeset{} = changeset} = Archives.delete_archive(archive)

      assert "Deployment releases exist which use the Archive" in errors_on(changeset).deployment_releases

      assert {:ok, _} = Archives.get(product, archive.uuid)
    end
  end

  # Whoever builds an archive chooses its UUID, so another org can upload one
  # with the same UUID as yours. Its file must not land on yours, or take yours
  # with it when deleted.
  describe "where archive files are stored" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      other_org = Fixtures.org_fixture(user)

      %{
        tmp_dir: tmp_dir,
        product: Fixtures.product_fixture(user, org),
        org_key: Fixtures.org_key_fixture(org, user, tmp_dir),
        other_product: Fixtures.product_fixture(user, other_org),
        other_org_key: Fixtures.org_key_fixture(other_org, user, tmp_dir)
      }
    end

    test "a new archive is stored under its org and product", context do
      %{product: product, org_key: org_key, tmp_dir: tmp_dir} = context
      [path] = same_archive_signed_by(tmp_dir, [org_key])

      {:ok, archive} = Archives.create(product, path)

      assert archive.storage_key == "/archives/#{product.org_id}/#{product.id}/#{archive.uuid}.fw"
      assert stored(archive.storage_key) == File.read!(path)
      assert Archives.url(archive) =~ "/uploads#{archive.storage_key}"
    end

    test "another org's archive with the same UUID gets its own file", context do
      %{product: product, org_key: org_key, other_product: other_product, other_org_key: other_org_key} = context
      [path, other_path] = same_archive_signed_by(context.tmp_dir, [org_key, other_org_key])

      {:ok, archive} = Archives.create(product, path)
      {:ok, other} = Archives.create(other_product, other_path)

      assert other.uuid == archive.uuid
      assert stored(archive.storage_key) == File.read!(path)
      assert stored(other.storage_key) == File.read!(other_path)

      {:ok, _} = Archives.delete_archive(other)
      :ok = perform_job(DeleteArchive, %{"archive_path" => other.storage_key})

      assert stored(other.storage_key) == :gone
      assert stored(archive.storage_key) == File.read!(path)
    end

    test "an archive from before keeps its file, and another org's can't reach it", context do
      %{product: product, org_key: org_key, other_product: other_product, other_org_key: other_org_key} = context
      [path, other_path] = same_archive_signed_by(context.tmp_dir, [org_key, other_org_key])
      {:ok, archive} = Archives.create(product, path)
      archive = from_before_storage_keys(archive)
      legacy_path = "/archives/#{archive.uuid}.fw"

      assert Archives.url(archive) =~ "/uploads#{legacy_path}"

      {:ok, other} = Archives.create(other_product, other_path)

      assert other.storage_key != legacy_path
      assert stored(legacy_path) == File.read!(path)

      {:ok, _} = Archives.delete_archive(other)
      :ok = perform_job(DeleteArchive, %{"archive_path" => other.storage_key})

      assert stored(legacy_path) == File.read!(path)

      {:ok, _} = Archives.delete_archive(archive)

      assert_enqueued(worker: DeleteArchive, args: %{"archive_path" => legacy_path})

      :ok = perform_job(DeleteArchive, %{"archive_path" => legacy_path})

      assert stored(legacy_path) == :gone
    end

    # Before, the same UUID in two products meant one file, so deleting either
    # archive took it from the other.
    test "a file two archives from before share stays until neither uses it", context do
      %{product: product, org_key: org_key, other_product: other_product, other_org_key: other_org_key} = context
      [path, other_path] = same_archive_signed_by(context.tmp_dir, [org_key, other_org_key])
      {:ok, archive} = Archives.create(product, path)
      {:ok, other} = Archives.create(other_product, other_path)
      archive = from_before_storage_keys(archive)
      other = from_before_storage_keys(other)
      legacy_path = "/archives/#{archive.uuid}.fw"

      {:ok, _} = Archives.delete_archive(other)
      :ok = perform_job(DeleteArchive, %{"archive_path" => legacy_path})

      assert stored(legacy_path) != :gone

      # The first delete's job has run. The test's single transaction would
      # otherwise give the second the same args and `scheduled_at`, which an
      # old unique index on `oban_jobs` refuses.
      Repo.delete_all(Oban.Job)

      {:ok, _} = Archives.delete_archive(archive)
      :ok = perform_job(DeleteArchive, %{"archive_path" => legacy_path})

      assert stored(legacy_path) == :gone
    end

    test "an archive deleted and uploaded again before its old file goes keeps its file", context do
      %{product: product, org_key: org_key} = context
      [path] = same_archive_signed_by(context.tmp_dir, [org_key])

      {:ok, archive} = Archives.create(product, path)
      {:ok, _} = Archives.delete_archive(archive)
      {:ok, again} = Archives.create(product, path)

      assert again.storage_key == archive.storage_key

      :ok = perform_job(DeleteArchive, %{"archive_path" => archive.storage_key})

      assert stored(again.storage_key) == File.read!(path)
    end
  end

  # One unsigned archive, signed with each key. Signing doesn't change its
  # meta.conf, so every copy has the same UUID, as an archive built to match
  # another org's would.
  defp same_archive_signed_by(tmp_dir, org_keys) do
    {:ok, _} = Support.Archives.create_archive(tmp_dir, "same")

    for org_key <- org_keys do
      {:ok, path} = Support.Archives.sign_archive(tmp_dir, org_key.name, "same", "same-#{org_key.id}")
      path
    end
  end

  # How an archive uploaded before storage keys looks: no key, and its file at
  # the path its UUID alone made.
  defp from_before_storage_keys(archive) do
    legacy_path = "/archives/#{archive.uuid}.fw"
    File.cp!(local_file(archive.storage_key), local_file(legacy_path))
    File.rm!(local_file(archive.storage_key))

    archive
    |> Ecto.Changeset.change(storage_key: nil)
    |> Repo.update!()
  end

  defp stored(path) do
    case File.read(local_file(path)) do
      {:ok, contents} -> contents
      {:error, :enoent} -> :gone
    end
  end

  defp local_file(path), do: Path.join(NervesHub.Uploads.File.local_path(), path)
end
