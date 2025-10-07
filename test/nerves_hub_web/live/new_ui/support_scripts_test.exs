defmodule NervesHubWeb.Live.NewUI.SupportScriptsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Scripts

  setup %{user: user, org: org} = context do
    [product: Fixtures.product_fixture(user, org, %{name: "Amazing"})]
    context
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

  describe "pagination" do
    test "no pagination when less than 25 support scripts", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      {:ok, _script} = Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts")
      |> refute_has("button", text: "25", timeout: 1000)
    end

    test "paginate when more than 25 support scripts", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      for i <- 1..26 do
        {:ok, _script} =
          Scripts.create(product, user, %{name: "MOTD #{i}", text: "NervesMOTD.print()"})
      end

      scripts = Scripts.all_by_product(product)
      [first_script | _] = scripts |> Enum.sort_by(& &1.name)

      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("button", text: "25", timeout: 1000)
      |> assert_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_script.name, exact: true, timeout: 1000)
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

    test "add script with tags", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/scripts/new")
      |> fill_in("Name", with: "MOTD")
      |> fill_in("Script code", with: "NervesMOTD.print()")
      |> fill_in("Tags", with: "hello,world")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("td", text: "MOTD")
      |> assert_has("span", text: "hello")
      |> assert_has("span", text: "world")
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
      |> fill_in("Name", with: "MOTD")
      |> fill_in("Script code", with: "dbg(NervesMOTD.print())")
      |> fill_in("Tags", with: "hello,world")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/scripts")
      |> assert_has("td", text: "MOTD")
      |> assert_has("span", text: "hello")
      |> assert_has("span", text: "world")

      assert %{text: "dbg(NervesMOTD.print())"} = Scripts.get!(script.id)
    end
  end
end
