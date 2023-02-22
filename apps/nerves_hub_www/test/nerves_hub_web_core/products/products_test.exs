defmodule NervesHubWebCore.ProductsTest do
  use NervesHubWebCore.DataCase, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.{Products, Accounts}

  describe "products" do
    alias NervesHubWebCore.Products.Product

    @valid_attrs %{name: "some name"}
    @update_attrs %{name: "some updated name"}
    @invalid_attrs %{name: nil}

    setup do
      {:ok, Fixtures.standard_fixture()}
    end

    test "get_products_by_user_and_org returns products for user", %{
      product: product,
      user: user,
      org: org
    } do
      assert Products.get_products_by_user_and_org(user, org) == [product]
    end

    test "get_product!/1 returns the product with given id", %{product: product} do
      assert Products.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product", %{org: org, user: user} do
      params = Enum.into(%{org_id: org.id}, @valid_attrs)
      assert {:ok, %Product{} = product} = Products.create_product(user, params)
      assert product.name == "some name"
    end

    test "create_product/1 adds user to product", %{org: org, user: user} do
      params = Enum.into(%{org_id: org.id}, @valid_attrs)
      assert {:ok, %Product{} = product} = Products.create_product(user, params)

      user_products = Products.get_products_by_user_and_org(user, org)
      assert Enum.member?(user_products, product)
    end

    test "create_product/1 with invalid data returns error changeset", %{user: user} do
      assert {:error, %Ecto.Changeset{}} = Products.create_product(user, @invalid_attrs)
    end

    test "create_product/1 fails with duplicate names", %{user: user, org: org} do
      params = %{org_id: org.id, name: "same name"}
      {:ok, _product} = Products.create_product(user, params)
      assert {:error, %Ecto.Changeset{}} = Products.create_product(user, params)
    end

    test "update_product/2 with valid data updates the product", %{product: product} do
      assert {:ok, %Product{} = product} = Products.update_product(product, @update_attrs)

      assert product.name == "some updated name"
    end

    test "update_product/2 with invalid data returns error changeset", %{product: product} do
      assert {:error, %Ecto.Changeset{}} = Products.update_product(product, @invalid_attrs)
      assert product == Products.get_product!(product.id)
    end

    test "delete_product/1 deletes the product" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org, %{name: "a product"})

      assert {:ok, %Product{}} = Products.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset", %{product: product} do
      assert %Ecto.Changeset{} = Products.change_product(product)
    end

    test "add user and remove user from a product", %{org: org, product: product} do
      user = Fixtures.user_fixture()
      assert {:ok, _product_user} = Products.add_product_user(product, user, %{role: :admin})
      assert [^product] = Products.get_products_by_user_and_org(user, org)
      assert :ok = Products.remove_product_user(product, user)
      assert [] = Products.get_products_by_user_and_org(user, org)
    end

    test "Unable to remove last user from org", %{product: product, user: user} do
      assert {:error, :last_user} = Products.remove_product_user(product, user)
    end

    test "List products from an org where the user has a comparable org role", %{
      org: org,
      product: product
    } do
      user = Fixtures.user_fixture()
      Accounts.add_org_user(org, user, %{role: :read})
      assert [^product] = Products.get_products_by_user_and_org(user, org)
    end

    test "create devices CSV IO", %{
      device: device,
      device_certificate: db_cert,
      product: product,
      org: org
    } do
      ##
      # Need to create a second certificate without a DER saved to test JSON
      # TODO: Remove when DERs are saved
      %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)

      otp_cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca1, ca1_key)

      %{db_cert: db_cert_no_der} =
        Fixtures.device_certificate_fixture_without_der(device, otp_cert)

      # Generate CSV
      csv_io = Products.devices_csv(product)

      [[id, desc, tags, pname, oname, cert_io] | _] = NimbleCSV.RFC4180.parse_string(csv_io)

      assert id == device.identifier
      assert desc == device.description || ""
      assert String.split(tags, ",") == device.tags
      assert pname == product.name
      assert oname == org.name

      String.split(cert_io, "\n\n")
      |> Enum.each(fn
        "{" <> _ = cert_json ->
          # TODO: Remove testing JSON when DERs saved
          parsed_cert = Jason.decode!(cert_json)

          assert parsed_cert["serial"] == db_cert_no_der.serial
          assert parsed_cert["not_before"] == DateTime.to_iso8601(db_cert_no_der.not_before)
          assert parsed_cert["not_after"] == DateTime.to_iso8601(db_cert_no_der.not_after)
          assert Base.decode16!(parsed_cert["aki"]) == db_cert_no_der.aki
          assert Base.decode16!(parsed_cert["ski"]) == db_cert_no_der.ski

        "---" <> _ = cert_pem ->
          assert X509.Certificate.from_pem!(cert_pem) == X509.Certificate.from_der!(db_cert.der)

        _ ->
          :ignore
      end)
    end
  end
end
