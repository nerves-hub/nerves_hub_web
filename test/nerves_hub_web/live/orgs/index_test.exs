defmodule NervesHubWeb.Live.Orgs.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Products

  describe "no org memberships" do
    test "no orgs listed" do
      user = NervesHub.Fixtures.user_fixture()

      token = NervesHub.Accounts.create_user_session_token(user)

      build_conn()
      |> init_test_session(%{"user_token" => token})
      |> visit("/orgs")
      |> assert_has("h3", text: "You aren't a member of any organizations.")
    end
  end

  describe "has orgs memberships" do
    test "all orgs listed", %{conn: conn, org: org} do
      conn
      |> visit("/orgs")
      |> assert_has("h1", text: "Organizations")
      |> assert_has("h3", text: org.name)
    end
  end

  describe "product banner display" do
    test "shows product with banner background", %{conn: conn, product: product, tmp_dir: tmp_dir} do
      banner_path = create_test_image(tmp_dir, "banner.png")
      {:ok, _product} = Products.update_product_banner(product, banner_path)

      conn
      |> visit("/orgs")
      |> assert_has("a", text: product.name)
      |> assert_has("a[style*='background-image']")
    end

    test "shows product without banner background when no banner", %{conn: conn, product: product} do
      conn
      |> visit("/orgs")
      |> assert_has("a", text: product.name)
      |> refute_has("div[style*='background-image']")
    end
  end

  defp create_test_image(dir, filename) do
    path = Path.join(dir, filename)

    png_data =
      <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119,
        83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0,
        73, 69, 78, 68, 174, 66, 96, 130>>

    File.write!(path, png_data)
    path
  end
end
