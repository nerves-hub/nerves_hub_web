defmodule NervesHubWeb.ScriptControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Scripts
  alias NervesHub.Fixtures

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "new command" do
    test "renders form with valid request params", %{conn: conn, org: org, product: product} do
      new_conn = get(conn, Routes.script_path(conn, :new, org.name, product.name))

      assert html_response(new_conn, 200) =~ "Add Script"
    end
  end

  describe "create command" do
    test "redirects to index when data is valid", %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{
        name: "MOTD",
        text: "NervesMOTD.print()"
      }

      # check that we end up in the right place
      conn =
        post(conn, Routes.script_path(conn, :create, org.name, product.name), command: params)

      assert redirected_to(conn, 302) =~
               Routes.script_path(conn, :index, org.name, product.name)

      conn = get(conn, Routes.script_path(conn, :index, org.name, product.name))
      assert html_response(conn, 200) =~ params.name
    end
  end

  describe "update command" do
    test "redirects to listing when data is valid", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, command} = Scripts.create(product, %{name: "MOTD", text: "NervesMOTD>print()"})

      params = %{
        text: "NervesMOTD.print()"
      }

      conn =
        put(conn, Routes.script_path(conn, :update, org.name, product.name, command.id),
          command: params
        )

      assert redirected_to(conn) == Routes.script_path(conn, :index, org.name, product.name)
      assert %{text: "NervesMOTD.print()"} = Scripts.get!(command.id)
    end
  end

  describe "delete product" do
    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      {:ok, command} = Scripts.create(product, %{name: "MOTD", text: "NervesMOTD.print()"})
      path = Routes.script_path(conn, :delete, org.name, product.name, command.id)
      conn = delete(conn, path)
      assert redirected_to(conn) == Routes.script_path(conn, :index, org.name, product.name)
    end
  end
end
