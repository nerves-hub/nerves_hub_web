defmodule NervesHubWeb.FirmwareControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Fixtures

  describe "download firmware" do
    test "downloads chosen firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn = get(conn, ~p"/org/#{org}/#{product}/firmware/#{firmware}/download")

      assert redirected_to(conn) == firmware.upload_metadata.public_path
    end

    test "a view member can't download firmware", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      NervesHub.Repo.update_all(OrgUser, set: [role: :view])

      assert_error_sent(401, fn ->
        get(conn, ~p"/org/#{org}/#{product}/firmware/#{firmware}/download")
      end)
    end

    test "a custom role member can download firmware if the role grants it", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      give_custom_role(org, user, ["firmware:download"])

      conn = get(conn, ~p"/org/#{org}/#{product}/firmware/#{firmware}/download")

      assert redirected_to(conn) == firmware.upload_metadata.public_path
    end

    test "a custom role member can't download firmware otherwise", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      give_custom_role(org, user, ["firmware:upload"])

      assert_error_sent(401, fn ->
        get(conn, ~p"/org/#{org}/#{product}/firmware/#{firmware}/download")
      end)
    end

    test "404s for firmware that does not exist", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/firmware/#{Ecto.UUID.generate()}/download")
      end)
    end
  end

  defp give_custom_role(org, user, permissions) do
    role = Fixtures.org_role_fixture(org, %{permissions: permissions})
    {:ok, org_user} = NervesHub.Accounts.get_org_user(org, user)
    {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, role)
  end
end
