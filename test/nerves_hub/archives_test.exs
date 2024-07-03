defmodule NervesHub.ArchivesTest do
  use NervesHub.DataCase

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
          tmp_dir,
          org_key.name,
          "manifest",
          "signed-manifest",
          %{
            platform: "generic",
            architecture: "generic",
            version: "0.1.0"
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
end
