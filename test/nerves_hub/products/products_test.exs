defmodule NervesHub.ProductsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.Product

  describe "products" do
    @valid_attrs %{name: "some name"}
    @invalid_attrs %{name: nil}

    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)

      %{user: user, org: org, product: product}
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

    test "create_product/1 defaults require_unique_firmware_version to true for new products",
         %{org: org} do
      params = Enum.into(%{org_id: org.id}, @valid_attrs)
      assert {:ok, %Product{require_unique_firmware_version: true}} = Products.create_product(params)
    end

    test "update_product/2 toggles require_unique_firmware_version", %{org: org} do
      {:ok, product} =
        Products.create_product(%{name: "toggle me", org_id: org.id, require_unique_firmware_version: false})

      assert product.require_unique_firmware_version == false

      assert {:ok, %Product{require_unique_firmware_version: true}} =
               Products.update_product(product, %{require_unique_firmware_version: true})
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

    test "stream and reduce devices from a product", %{
      user: user,
      product: product,
      org: org,
      tmp_dir: tmp_dir
    } do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      %{db_cert: db_cert} = Fixtures.device_certificate_fixture(device)

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
      devices_query = Devices.filter_query(product, user, %{sort: {:asc, :identifier}})

      {:ok, csv_io} =
        Products.devices_export_reducer(devices_query, product, [], fn res, line -> {:ok, [line | res]} end)

      [[id, desc, tags, product_name, org_name, cert_io] | _] = csv_io

      assert id == device.identifier
      assert desc == device.description || ""
      assert String.split(tags, ",") == device.tags
      assert product_name == product.name
      assert org_name == org.name

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

  describe "custom health metric labels" do
    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)

      %{user: user, org: org, product: product}
    end

    test "returns an empty map when no labels are set", %{product: product} do
      assert Products.custom_health_metrics_labels(product) == %{}
    end

    test "setting a label inserts and is returned as a map", %{product: product} do
      assert {:ok, label} = Products.set_custom_health_metrics_label(product, "cpu_temp", "CPU Heat")

      assert label.key == "cpu_temp"
      assert label.label == "CPU Heat"
      assert Products.custom_health_metrics_labels(product) == %{"cpu_temp" => "CPU Heat"}
    end

    test "setting a label trims surrounding whitespace", %{product: product} do
      assert {:ok, label} =
               Products.set_custom_health_metrics_label(product, "cpu_temp", "  CPU Heat  ")

      assert label.label == "CPU Heat"
    end

    test "setting a label again updates the existing label", %{product: product} do
      {:ok, _} = Products.set_custom_health_metrics_label(product, "cpu_temp", "CPU Heat")
      {:ok, _} = Products.set_custom_health_metrics_label(product, "cpu_temp", "Processor Temp")

      assert Products.custom_health_metrics_labels(product) == %{"cpu_temp" => "Processor Temp"}
    end

    test "setting a blank label removes the custom label", %{product: product} do
      {:ok, _} = Products.set_custom_health_metrics_label(product, "cpu_temp", "CPU Heat")

      assert {:ok, nil} = Products.set_custom_health_metrics_label(product, "cpu_temp", "   ")
      assert Products.custom_health_metrics_labels(product) == %{}
    end

    test "deleting a label removes it", %{product: product} do
      {:ok, _} = Products.set_custom_health_metrics_label(product, "cpu_temp", "CPU Heat")

      assert :ok = Products.delete_custom_health_metrics_label(product, "cpu_temp")
      assert Products.custom_health_metrics_labels(product) == %{}
    end

    test "labels are scoped to a single product", %{user: user, org: org, product: product} do
      other_product = Fixtures.product_fixture(user, org, %{name: "Other"})

      {:ok, _} = Products.set_custom_health_metrics_label(product, "cpu_temp", "CPU Heat")

      assert Products.custom_health_metrics_labels(product) == %{"cpu_temp" => "CPU Heat"}
      assert Products.custom_health_metrics_labels(other_product) == %{}
    end
  end

  describe "get_products/2 with counts" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      scope =
        user
        |> Scope.for_user()
        |> Scope.put_org(org)

      %{scope: scope, org: org, product: product, firmware: firmware}
    end

    test "counts connected and disconnected devices", context do
      connect(context, :connected)
      connect(context, :disconnected)
      connect(context, :disconnected)

      assert [product] = Products.get_products(context.scope, with_counts: true)
      assert product.connected_devices_count == 1
      assert product.disconnected_devices_count == 2
    end

    test "counts a device that has never connected as disconnected", context do
      Fixtures.device_fixture(context.org, context.product, context.firmware)

      assert [product] = Products.get_products(context.scope, with_counts: true)
      assert product.connected_devices_count == 0
      assert product.disconnected_devices_count == 1
    end

    test "does not count soft deleted devices", context do
      connect(context, :connected)
      connect(context, :disconnected)

      {:ok, _} = Devices.delete_device(connect(context, :connected))
      {:ok, _} = Devices.delete_device(connect(context, :disconnected))

      assert [product] = Products.get_products(context.scope, with_counts: true)
      assert product.connected_devices_count == 1
      assert product.disconnected_devices_count == 1
    end

    defp connect(context, status) do
      device = Fixtures.device_fixture(context.org, context.product, context.firmware)
      Fixtures.device_connection_fixture(device, %{status: status})
      device
    end
  end

  describe "Product changesets" do
    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      %{user: user, org: org}
    end

    test "change_user_role/2 validates role is required", %{org: org} do
      org_user = %OrgUser{org_id: org.id}
      changeset = Product.change_user_role(org_user, %{})
      refute changeset.valid?
      assert changeset.errors[:role] != nil
    end

    test "change_user_role/2 is valid with a role", %{org: org} do
      org_user = %OrgUser{org_id: org.id}
      changeset = Product.change_user_role(org_user, %{role: :admin})
      assert changeset.valid?
    end

    test "changeset/2 with nil name passes nil through trim fallback", %{org: org} do
      changeset = Product.changeset(%Product{}, %{name: nil, org_id: org.id})
      refute changeset.valid?
    end
  end
end
