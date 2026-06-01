defmodule NervesHubWeb.Live.LayoutTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Products

  test "can logout", %{conn: conn} do
    conn
    |> visit("/")
    |> click_link("Log out")
    |> assert_path("/login")
  end

  describe "product banner in sidebar layout" do
    test "shows banner background on product pages when banner exists", %{
      conn: conn,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      banner_path = create_test_image(tmp_dir, "banner.png")
      {:ok, _product} = Products.update_product_banner(product, banner_path)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div[style*='background-image']")
    end

    test "does not show banner background on product pages when no banner", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
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
