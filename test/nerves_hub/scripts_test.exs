defmodule NervesHub.ScriptsTest do
  use NervesHub.DataCase

  alias NervesHub.Scripts
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  describe "creating a command" do
    test "successful", %{product: product} do
      {:ok, command} =
        Scripts.create(product, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      assert command.product_id == product.id
    end
  end
end
