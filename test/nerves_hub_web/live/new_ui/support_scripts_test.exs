defmodule NervesHubWeb.Live.NewUI.SupportScriptsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Scripts

  setup %{conn: conn, user: user, org: org} do
    conn = init_test_session(conn, %{"new_ui" => true})

    [conn: conn, product: Fixtures.product_fixture(user, org, %{name: "Amazing"})]
  end

  describe "list" do
    test "show a message if there are no support scripts", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("span", text: "#{product.name} doesn’t have any Support Scripts")
    end

    test "shows all support scripts for a product", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      {:ok, _script} = Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("td", text: "MOTD")
    end
  end

  describe "delete" do
    test "removes support script", %{conn: conn, org: org, product: product, user: user} do
      {:ok, script} = Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts/#{script.id}/edit")
      |> assert_has("input", value: script.name)
      |> click_button("Delete Script")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("span", text: "#{product.name} doesn’t have any Support Scripts")
    end
  end

  describe "new" do
    test "requires a name and text", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts/new")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts/new")
      |> assert_has("p", text: "can't be blank", count: 2)
      |> fill_in("Name", with: "MOTD")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts/new")
      |> assert_has("p", text: "can't be blank", count: 1)
      |> fill_in("Script code", with: "NervesMOTD.print()")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("td", text: "MOTD")
    end
  end

  describe "edit" do
    test "requires a name and text", %{conn: conn, org: org, product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts/#{script.id}/edit")
      |> fill_in("Name", with: "")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts/#{script.id}/edit")
      |> assert_has("p", text: "can't be blank", count: 1)
      |> fill_in("Name", with: "MOTDDDDD")
      |> fill_in("Script code", with: "dbg(NervesMOTD.print())")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("td", text: "MOTDDDDD")

      assert %{text: "dbg(NervesMOTD.print())"} = Scripts.get!(script.id)
    end
  end
end
