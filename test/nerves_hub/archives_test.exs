defmodule NervesHub.ArchivesTest do
  use NervesHub.DataCase, async: true
  use Oban.Testing, repo: NervesHub.Repo

  alias NervesHub.Archives
  alias NervesHub.Fixtures
  alias NervesHub.Support

  describe "creating archives" do
    @tag :tmp_dir
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
  end

  describe "delete_archive/1" do
    test "delete archive" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      archive = Fixtures.archive_fixture(org_key, product)

      {:ok, _} = Archives.delete_archive(archive)

      assert_enqueued(
        worker: NervesHub.Workers.DeleteArchive,
        args: %{
          "archive_path" => "/archives/#{archive.uuid}.fw"
        }
      )

      assert {:error, :not_found} = Archives.get(product, archive.uuid)
    end
  end
end
