defmodule NervesHub.ProductsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.{Products, Accounts}

  describe "products" do
    alias NervesHub.Products.Product

    @valid_attrs %{name: "some name"}
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

    test "create_product/1 with valid data creates a product", %{org: org} do
      params = Enum.into(%{org_id: org.id}, @valid_attrs)
      assert {:ok, %Product{} = product} = Products.create_product(params)
      assert product.name == "some name"
    end

    test "create_product/1 adds user to product", %{org: org} do
      params = Enum.into(%{org_id: org.id}, @valid_attrs)
      assert {:ok, %Product{}} = Products.create_product(params)
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product(@invalid_attrs)
    end

    test "create_product/1 fails with duplicate names", %{org: org} do
      params = %{org_id: org.id, name: "same name"}
      {:ok, _product} = Products.create_product(params)
      assert {:error, %Ecto.Changeset{}} = Products.create_product(params)
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

    test "List products from an org where the user has a comparable org role", %{
      org: org,
      product: product
    } do
      user = Fixtures.user_fixture()
      Accounts.add_org_user(org, user, %{role: :view})
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
