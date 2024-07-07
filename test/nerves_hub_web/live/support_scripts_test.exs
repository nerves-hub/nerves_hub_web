defmodule NervesHubWeb.Live.SupportScriptsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Scripts
  alias NervesHub.Fixtures

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org, %{name: "Amazing"})]
  end

  describe "list" do
    test "show a message if there are no support scripts", %{
      conn: conn,
      product: product
    } do
      conn
      |> visit("/products/#{hashid(product)}/scripts")
      |> assert_has("h3", text: "#{product.name} doesn’t have any Support Scripts yet")
    end

    test "shows all support scripts for a product", %{conn: conn, product: product} do
      {:ok, _command} = Scripts.create(product, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/products/#{hashid(product)}/scripts")
      |> assert_has("td", text: "MOTD")
    end
  end

  describe "delete" do
    test "removes support script", %{conn: conn, product: product} do
      {:ok, _command} = Scripts.create(product, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/products/#{hashid(product)}/scripts")
      |> assert_has("td", text: "MOTD")
      |> click_link("Delete")
      |> assert_has("h3", text: "#{product.name} doesn’t have any Support Scripts yet")
    end
  end

  describe "new" do
    test "requires a name and text", %{conn: conn, product: product} do
      conn
      |> visit("/products/#{hashid(product)}/scripts/new")
      |> click_button("Add Script")
      |> assert_path("/products/#{hashid(product)}/scripts/new")
      |> assert_has("span", text: "can't be blank", count: 2)
      |> fill_in("Script name", with: "MOTD")
      |> click_button("Add Script")
      |> assert_path("/products/#{hashid(product)}/scripts/new")
      |> assert_has("span", text: "can't be blank", count: 1)
      |> fill_in("Script text", with: "NervesMOTD.print()")
      |> click_button("Add Script")
      |> assert_path("/products/#{hashid(product)}/scripts")
      |> assert_has("td", text: "MOTD")
    end
  end

  describe "edit" do
    test "requires a name and text", %{conn: conn, product: product} do
      {:ok, script} = Scripts.create(product, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/products/#{hashid(product)}/scripts/#{script.id}/edit")
      |> fill_in("Script name", with: "")
      |> click_button("Save Changes")
      |> assert_path("/products/#{hashid(product)}/scripts/#{script.id}/edit")
      |> assert_has("span", text: "can't be blank", count: 1)
      |> fill_in("Script name", with: "MOTDDDDD")
      |> fill_in("Script text", with: "dbg(NervesMOTD.print())")
      |> click_button("Save Changes")
      |> assert_path("/products/#{hashid(product)}/scripts")
      |> assert_has("td", text: "MOTDDDDD")

      assert %{text: "dbg(NervesMOTD.print())"} = Scripts.get!(script.id)
    end
  end
end
