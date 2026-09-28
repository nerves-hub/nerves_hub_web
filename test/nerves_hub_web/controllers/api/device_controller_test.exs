defmodule NervesHubWeb.API.DeviceControllerTest do
  use NervesHubWeb.APIConnCase, async: true
  use Mimic
  use AssertEventually, timeout: 500, interval: 50

  import Phoenix.ChannelTest

  alias NervesHub.Accounts
  alias NervesHub.AdvancedQueryFixtures
  alias NervesHub.AuditLogs
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias NervesHub.Scripts.Runner
  alias NervesHubWeb.API.Schemas.DeviceSchemas
  alias Phoenix.Socket.Broadcast

  describe "create devices" do
    test "renders device when data is valid", %{conn: conn, org: org, product: product} do
      identifier = "api-device-1234"

      device = %{
        identifier: identifier,
        description: "test device",
        tags: ["test"],
        update_mode: :automatic
      }

      conn = post(conn, Routes.api_device_path(conn, :create, org.name, product.name), device)
      assert json_response(conn, 201)["data"]

      conn =
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier))

      assert json_response(conn, 200)["data"]["identifier"] == identifier
      assert json_response(conn, 200)["data"]["updates_enabled"] == true
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "with shared_secret, also returns the device's own key and secret, and audits it", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      params = %{identifier: "api-device-with-secret", shared_secret: true}

      data =
        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["identifier"] == "api-device-with-secret"
      assert %{"key" => "nhd_" <> _ = key, "secret" => secret} = data["shared_secret"]

      assert {:ok, auth} = Devices.get_shared_secret_auth(key)
      assert auth.secret == secret
      assert auth.device.identifier == "api-device-with-secret"
      assert [%{actor_id: actor_id}] = NervesHub.AuditLogs.logs_for(auth.device)
      assert actor_id == user.id

      shown =
        conn
        |> get(Routes.api_device_path(conn, :show, org.name, product.name, "api-device-with-secret"))
        |> json_response(200)
        |> Map.fetch!("data")

      refute Map.has_key?(shown, "shared_secret")
    end

    test ~s(accepts shared_secret as the string "true", as form params send it), %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{identifier: "api-device-form", shared_secret: "true"}

      data =
        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
        |> json_response(201)
        |> Map.fetch!("data")

      assert %{"key" => "nhd_" <> _} = data["shared_secret"]
    end

    test ~s(accepts shared_secret as "1", as the device's boolean fields do), %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{identifier: "api-device-one", shared_secret: "1"}

      data =
        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
        |> json_response(201)
        |> Map.fetch!("data")

      assert %{"key" => "nhd_" <> _} = data["shared_secret"]
    end

    test "refuses a shared_secret that isn't a boolean, and creates no device", %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{identifier: "api-device-on", shared_secret: "on"}

      assert conn
             |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
             |> json_response(422) ==
               %{"errors" => %{"detail" => ~s(shared_secret must be true or false, got "on".)}}

      assert {:error, :not_found} = Devices.get_device_by(identifier: "api-device-on")
    end

    test "without shared_secret, creates no shared secret", %{conn: conn, org: org, product: product} do
      data =
        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), %{identifier: "api-device-plain"})
        |> json_response(201)
        |> Map.fetch!("data")

      refute Map.has_key?(data, "shared_secret")
      assert Repo.aggregate(Devices.SharedSecretAuth, :count) == 0
    end

    test "with shared_secret, creates no secret when the device cannot be created", %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{identifier: "api-device-taken", shared_secret: true}
      path = Routes.api_device_path(conn, :create, org.name, product.name)

      assert conn |> post(path, params) |> json_response(201)
      assert conn |> post(path, params) |> json_response(422)

      assert Repo.aggregate(Devices.SharedSecretAuth, :count) == 1
    end

    test "with shared_secret, creates nothing when shared secrets aren't enabled", %{
      conn: conn,
      org: org,
      product: product
    } do
      stub(NervesHub.DeviceLink, :shared_secrets_enabled?, fn -> false end)
      params = %{identifier: "api-device-disabled", shared_secret: true}

      assert %{"errors" => %{"detail" => "Device shared secrets are not enabled" <> _}} =
               conn
               |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
               |> json_response(422)

      assert {:error, :not_found} = Devices.get_device_by(identifier: "api-device-disabled")
    end

    test "creates the device in the documented example", %{conn: conn, org: org, product: product} do
      %{"device" => fields} = example = DeviceSchemas.DeviceCreationRequest.schema().example

      conn
      |> post(Routes.api_device_path(conn, :create, org.name, product.name), example)
      |> json_response(201)

      device = Repo.get_by!(Device, identifier: fields["identifier"])
      assert device.product_id == product.id
      assert device.description == fields["description"]
      assert device.tags == fields["tags"]
      assert to_string(device.update_mode) == fields["update_mode"]
      assert device.managed_updates_allowed == fields["managed_updates_allowed"]
    end

    test "saves each documented field, from a device object or the top level", %{
      conn: conn,
      org: org,
      product: product
    } do
      fields = %{
        description: "on the bench",
        tags: "bench, rev-b",
        update_mode: "device_managed",
        connecting_code: "IO.puts(:hello)",
        managed_updates_allowed: true
      }

      for {shape, wrap} <- body_shapes() do
        identifier = "api-device-#{shape}"

        conn
        |> post(
          Routes.api_device_path(conn, :create, org.name, product.name),
          wrap.(Map.put(fields, :identifier, identifier))
        )
        |> json_response(201)

        device = Repo.get_by!(Device, identifier: identifier)
        assert device.description == "on the bench"
        assert device.tags == ["bench", "rev-b"]
        assert device.update_mode == :device_managed
        assert device.connecting_code == "IO.puts(:hello)"
        assert device.managed_updates_allowed
      end
    end

    test "reads only the device object when the body has one", %{conn: conn, org: org, product: product} do
      params = %{
        device: %{identifier: "api-device-in-object"},
        identifier: "api-device-at-top-level",
        description: "at the top level"
      }

      conn
      |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
      |> json_response(201)

      assert is_nil(Repo.get_by!(Device, identifier: "api-device-in-object").description)
      refute Repo.get_by(Device, identifier: "api-device-at-top-level")
    end

    test "with shared_secret beside a device object, also returns the device's own key and secret", %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{
        device: %{identifier: "api-device-object-with-secret", managed_updates_allowed: true},
        shared_secret: true
      }

      data =
        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["identifier"] == "api-device-object-with-secret"
      assert data["managed_updates_allowed"] == true
      assert %{"key" => "nhd_" <> _ = key} = data["shared_secret"]
      assert {:ok, auth} = Devices.get_shared_secret_auth(key)
      assert auth.device.identifier == "api-device-object-with-secret"
      assert auth.device.managed_updates_allowed
    end

    test "sets managed_updates_allowed, auditing it when it isn't the product's default", %{
      conn: conn,
      org: org,
      product: product,
      user: user
    } do
      refute product.default_managed_updates_allowed
      path = Routes.api_device_path(conn, :create, org.name, product.name)

      conn |> post(path, %{identifier: "api-device-granted", managed_updates_allowed: true}) |> json_response(201)
      conn |> post(path, %{identifier: "api-device-default", managed_updates_allowed: false}) |> json_response(201)

      granted = Repo.get_by!(Device, identifier: "api-device-granted")
      assert granted.managed_updates_allowed

      assert [%{actor_id: actor_id, description: description}] = AuditLogs.logs_for(granted)
      assert actor_id == user.id
      assert description == "User #{user.name} allowed device-managed updates for device api-device-granted"

      default = Repo.get_by!(Device, identifier: "api-device-default")
      refute default.managed_updates_allowed
      assert AuditLogs.logs_for(default) == []
    end

    test "refuses a managed_updates_allowed that isn't a boolean, and creates no device", %{
      conn: conn,
      org: org,
      product: product
    } do
      params = %{identifier: "api-device-sometimes", managed_updates_allowed: "sometimes"}

      assert conn
             |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
             |> json_response(422) ==
               %{"errors" => %{"detail" => ~s(managed_updates_allowed must be true or false, got "sometimes".)}}

      refute Repo.get_by(Device, identifier: "api-device-sometimes")
    end

    test "creates no device when managed_updates_allowed can't be saved", %{conn: conn, org: org, product: product} do
      expect(Updates, :set_managed_updates_allowed, fn device, true, _user ->
        changeset =
          device
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:managed_updates_allowed, "could not be saved")

        {:error, :update_with_audit, changeset, %{}}
      end)

      params = %{identifier: "api-device-unsaved-grant", managed_updates_allowed: true}

      assert conn
             |> post(Routes.api_device_path(conn, :create, org.name, product.name), params)
             |> json_response(422) ==
               %{"errors" => %{"managed_updates_allowed" => ["could not be saved"]}}

      refute Repo.get_by(Device, identifier: "api-device-unsaved-grant")
    end

    # `deployment_group_id` and `updates_enabled` were documented here once but
    # never saved.
    test "ignores fields a caller may not set, from a device object or the top level", %{
      conn: conn,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      other_org_key = Fixtures.org_key_fixture(other_org, other_user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})
      other_deployment_group = Fixtures.deployment_group_fixture(other_firmware, %{user: other_user})

      for {shape, wrap} <- body_shapes() do
        identifier = "api-device-planted-#{shape}"

        params = %{
          identifier: identifier,
          org_id: other_org.id,
          product_id: other_product.id,
          deployment_id: other_deployment_group.id,
          deployment_group_id: other_deployment_group.id,
          updates_enabled: false,
          status: "provisioned",
          deleted_at: DateTime.to_iso8601(DateTime.utc_now())
        }

        conn
        |> post(Routes.api_device_path(conn, :create, org.name, product.name), wrap.(params))
        |> json_response(201)

        device = Repo.get_by!(Device, identifier: identifier)
        assert device.org_id == org.id
        assert device.product_id == product.id
        assert is_nil(device.deployment_id)
        assert device.update_mode == :automatic
        assert device.status == :registered
        assert is_nil(device.deleted_at)
      end
    end
  end

  describe "bulk create devices (async processing)" do
    test "all devices are successfully imported", %{conn: conn, org: org, product: product} do
      json_import_data = File.read!("test/fixtures/devices_bulk_create/microchip_trust_and_go_manifest.json")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("format", "microchip_trust_and_go")
        |> post(Routes.api_device_path(conn, :bulk_import, org.name, product.name), json_import_data)

      assert response(conn, 201)

      eventually assert Repo.aggregate(Device, :count) == 5
      eventually assert Repo.aggregate(Notification, :count) == 1
    end

    test "all devices are successfully imported, with tags set", %{conn: conn, org: org, product: product} do
      json_import_data = File.read!("test/fixtures/devices_bulk_create/microchip_trust_and_go_manifest.json")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("format", "microchip_trust_and_go")
        |> put_req_header("tags", "snoot-boop")
        |> post(Routes.api_device_path(conn, :bulk_import, org.name, product.name), json_import_data)

      assert response(conn, 201)

      eventually assert Repo.aggregate(Device, :count) == 5
      eventually assert Repo.aggregate(Notification, :count) == 1

      assert Repo.all(Device) |> Enum.all?(fn d -> d.tags == ["snoot-boop"] end)
    end

    test "not all devices are successfully imported", %{conn: conn, org: org, product: product} do
      json_import_data = File.read!("test/fixtures/devices_bulk_create/microchip_trust_and_go_manifest.json")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("format", "microchip_trust_and_go")
        |> post(Routes.api_device_path(conn, :bulk_import, org.name, product.name), json_import_data)

      assert response(conn, 201)

      eventually assert Repo.aggregate(Device, :count) == 5
      eventually assert Repo.aggregate(Notification, :count) == 1
    end
  end

  describe "index" do
    test "lists all devices for an org", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "AllTheBoops"})
      product = Fixtures.product_fixture(user, org, %{name: "auto_boops"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware)

      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name))

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "connection_status" => "not_seen",
                   "deleted" => false,
                   "deployment_group" => nil,
                   "description" => nil,
                   "firmware_metadata" => %{
                     "architecture" => "x86_64",
                     "author" => "me",
                     "description" => "D ",
                     "fwup_version" => "1.0.0",
                     "id" => device.firmware_metadata.id,
                     "misc" => nil,
                     "platform" => "platform",
                     "product" => "auto_boops",
                     "uuid" => firmware.uuid,
                     "vcs_identifier" => nil,
                     "version" => "1.0.0"
                   },
                   "identifier" => device.identifier,
                   "last_communication" => "never",
                   "managed_updates_allowed" => false,
                   "online" => "not_seen",
                   "org_name" => "AllTheBoops",
                   "product_name" => "auto_boops",
                   "tags" => ["beta", "beta-edge"],
                   "update_mode" => "automatic",
                   "updates_blocked_until" => nil,
                   "updates_enabled" => true,
                   "version" => "1.0.0"
                 }
               ],
               "pagination" => %{
                 "page_number" => 1,
                 "page_size" => 10,
                 "total_entries" => 1,
                 "total_pages" => 1
               }
             }

      assert Enum.find(conn.assigns.devices, fn %{identifier: identifier} ->
               device.identifier == identifier
             end)
    end

    test "includes deployment group information", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware)
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      {:ok, _device} =
        Devices.update_device(device, %{deployment_id: deployment_group.id})

      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name))

      assert %{"data" => [device_data]} = json_response(conn, 200)
      assert device_data["identifier"] == device.identifier
      assert device_data["deployment_group"]["name"] == deployment_group.name
    end

    test "allows for page size and current page to be specified", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      for _ <- 1..20 do
        Fixtures.device_fixture(org, product, firmware)
      end

      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name, %{pagination: %{page_size: 5}}))

      assert %{"pagination" => %{"total_entries" => 20, "page_size" => 5, "page_number" => 1, "total_pages" => 4}} =
               json_response(conn, 200)

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{pagination: %{page_size: 10, page: 2}})
        )

      assert %{"pagination" => %{"total_entries" => 20, "page_size" => 10, "page_number" => 2, "total_pages" => 2}} =
               json_response(conn, 200)
    end

    test "allows for sorting to be specified", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      for num <- 1..20 do
        Fixtures.device_fixture(org, product, firmware, %{identifier: "sorting-#{num}"})
      end

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{sort: "identifier", sort_direction: "asc"})
        )

      assert %{"data" => [first_device | _], "pagination" => %{"total_entries" => 20}} = json_response(conn, 200)
      assert first_device["identifier"] == "sorting-1"

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{sort: "identifier", sort_direction: "desc"})
        )

      assert %{"data" => [first_device | _], "pagination" => %{"total_entries" => 20}} = json_response(conn, 200)
      assert first_device["identifier"] == "sorting-9"
    end

    test "allows for filtering: identifier", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      for num <- 1..20 do
        Fixtures.device_fixture(org, product, firmware, %{identifier: "identifier-filtering-#{num}"})
      end

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{
            filters: %{identifier: "identifier-filtering-1"}
          })
        )

      assert %{"pagination" => %{"total_entries" => 11}} = json_response(conn, 200)
    end

    test "allows for filtering: connection", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      for _ <- 1..20 do
        Fixtures.device_fixture(org, product, firmware)
      end

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{filters: %{connection: "not_seen"}})
        )

      assert %{"pagination" => %{"total_entries" => 20}} = json_response(conn, 200)
    end

    test "allows for filtering: health_status", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "DeployedOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "deployed_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      for num <- 1..20 do
        Fixtures.device_fixture(org, product, firmware, %{identifier: "health-status-#{num}"})
      end

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{filters: %{health_status: "unknown"}})
        )

      assert %{"pagination" => %{"total_entries" => 20}} = json_response(conn, 200)
    end

    test "does not return soft-deleted devices", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _device} =
        Fixtures.device_fixture(org, product, firmware)
        |> Devices.update_device(%{deleted_at: DateTime.utc_now()})

      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name))

      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index: advanced query" do
    setup %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "AdvancedQueryOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "advanced_query_product"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      hot = Fixtures.device_fixture(org, product, firmware, %{identifier: "aq-hot", tags: ["prod"]})
      cool = Fixtures.device_fixture(org, product, firmware, %{identifier: "aq-cool", tags: ["staging"]})

      %{conn: conn, org: org, product: product, firmware: firmware, hot: hot, cool: cool}
    end

    defp index_identifiers(conn, org, product, query) do
      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{filters: %{advanced_query: query}})
        )

      json_response(conn, 200)["data"] |> Enum.map(& &1["identifier"]) |> Enum.sort()
    end

    test "filters on each device's latest custom health metric value", %{
      conn: conn,
      org: org,
      product: product,
      hot: hot,
      cool: cool
    } do
      # Only the latest reading per device counts: "cool" once ran hot, but its
      # latest reading is below the threshold.
      AdvancedQueryFixtures.save_metric(hot, "cpu_temp", 80.0, 10)
      AdvancedQueryFixtures.save_metric(hot, "cpu_temp", 40.0, 100)
      AdvancedQueryFixtures.save_metric(cool, "cpu_temp", 30.0, 10)
      AdvancedQueryFixtures.save_metric(cool, "cpu_temp", 90.0, 100)

      assert index_identifiers(conn, org, product, ~s|metric:cpu_temp > 50|) == ["aq-hot"]
      assert index_identifiers(conn, org, product, ~s|metric:cpu_temp <= 50|) == ["aq-cool"]
    end

    test "supports boolean expressions combining metrics and other columns", %{
      conn: conn,
      org: org,
      product: product,
      hot: hot,
      cool: cool
    } do
      AdvancedQueryFixtures.save_metric(hot, "battery_soc", 15.0, 10)
      AdvancedQueryFixtures.save_metric(cool, "battery_soc", 80.0, 10)

      assert index_identifiers(
               conn,
               org,
               product,
               ~s|metric:battery_soc < 20 and tags contains "prod"|
             ) == ["aq-hot"]

      assert index_identifiers(
               conn,
               org,
               product,
               ~s|metric:battery_soc < 20 or tags contains "staging"|
             ) == ["aq-cool", "aq-hot"]
    end

    test "exercises columns that need the extra joins", %{conn: conn, org: org, product: product} do
      # update_status compiles against the inflight_update binding; neither
      # device has an inflight update.
      assert index_identifiers(conn, org, product, ~s|update_status is "not updating"|) == ["aq-cool", "aq-hot"]
      assert index_identifiers(conn, org, product, ~s|update_status is "updating"|) == []
    end

    test "filters on alarms, in the query and as filters", %{conn: conn, org: org, product: product, hot: hot} do
      # The alarm filters correlate an EXISTS against `device_alarms` back to
      # the listed device by its `:device` binding.
      Fixtures.device_alarms_fixture(hot, %{"CableDown" => "no link on the cable"})

      assert index_identifiers(conn, org, product, ~s|alarm_status = "with"|) == ["aq-hot"]
      assert index_identifiers(conn, org, product, ~s|alarm_status = "without"|) == ["aq-cool"]

      for filters <- [%{alarm_status: "with"}, %{alarm: "CableDown"}] do
        conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name, %{filters: filters}))
        assert [%{"identifier" => "aq-hot"}] = json_response(conn, 200)["data"]
      end
    end

    test "treats non-query input as a free-text search", %{conn: conn, org: org, product: product} do
      assert index_identifiers(conn, org, product, "aq-ho") == ["aq-hot"]
    end

    test "lets `deleted` in the query control soft-deleted visibility", %{
      conn: conn,
      org: org,
      product: product,
      cool: cool
    } do
      {:ok, _} = Devices.update_device(cool, %{deleted_at: DateTime.utc_now()})

      assert index_identifiers(conn, org, product, ~s|deleted = "true"|) == ["aq-cool"]
      assert index_identifiers(conn, org, product, ~s|deleted = "false"|) == ["aq-hot"]
      # without the query, the default exclusion still applies
      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name))
      assert json_response(conn, 200)["data"] |> Enum.map(& &1["identifier"]) == ["aq-hot"]
    end

    test "rejects an invalid query expression with the parse error", %{conn: conn, org: org, product: product} do
      conn =
        get(
          conn,
          Routes.api_device_path(conn, :index, org.name, product.name, %{
            filters: %{advanced_query: ~s|bogus_column = "x"|}
          })
        )

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail =~ "invalid advanced query"
      assert detail =~ "bogus_column"
    end
  end

  describe "show" do
    test "device that the user has access to, using nested url", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "device that the user does not have access to, using nested url", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, "abcd"))
      end)
      |> assert_authorization_error(404)
    end

    test "device that the user has access to, using short url", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "device that the user does not have access to, using short url", %{conn: conn} do
      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, "abcd"))
      end)
      |> assert_authorization_error(404)
    end

    test "device from another product in the same org, using nested url", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "Owning"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      sibling = Fixtures.product_fixture(user, org, %{name: "Sibling"})

      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, org.name, sibling.name, device.identifier))
      end)
      |> assert_authorization_error(404)
    end

    test "short url resolves a device even when the org has other products", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "Owning"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      # No product in this URL, so nothing to scope to. Guards the conditional
      # in Devices.scope_to_product/2.
      _sibling = Fixtures.product_fixture(user, org, %{name: "Sibling"})

      conn = get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "deleted device can be queried", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, device} =
        Fixtures.device_fixture(org, product, firmware)
        |> Devices.update_device(%{deleted_at: DateTime.utc_now()})

      conn =
        get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "device indicates if it has been deleted", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, device} =
        Fixtures.device_fixture(org, product, firmware)
        |> Devices.update_device(%{deleted_at: DateTime.utc_now()})

      conn =
        get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["deleted"] == true

      {:ok, device} = Devices.update_device(device, %{deleted_at: nil})

      conn =
        get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]["deleted"] == false
    end
  end

  describe "delete devices" do
    test "deletes chosen device", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      to_delete = Fixtures.device_fixture(org, product, firmware)

      # fully load all the associations
      to_delete = Devices.get_complete_device(to_delete.id)

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :delete, org.name, product.name, to_delete.identifier)
        )

      assert response(conn, 204)
    end

    test "does not have required role to delete chosen device", %{
      conn: conn,
      user: user,
      conn2: other_user_conn,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      to_delete = Fixtures.device_fixture(org, product, firmware)

      # fully load all the associations
      to_delete = Devices.get_complete_device(to_delete.id)

      assert_error_sent(404, fn ->
        delete(
          other_user_conn,
          Routes.api_device_path(conn, :delete, org.name, product.name, to_delete.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "update devices" do
    test "updates chosen device", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} =
        Devices.update_device(device, %{deployment_id: deployment_group.id})

      conn =
        put(
          conn,
          Routes.api_device_path(conn, :update, org.name, product.name, device.identifier),
          %{
            tags: ["a", "b", "c", "d"]
          }
        )

      assert json_response(conn, 201)["data"]

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)
        )

      assert json_response(conn, 200)
      assert conn.assigns.device.tags == ["a", "b", "c", "d"]
    end

    # `Device.changeset/2` casts the org, product and deployment group, so an
    # update passing the body straight through could move a device into
    # another org or onto another org's deployment group.
    # `deployment_group_id` and `updates_enabled` were documented here once but
    # never saved.
    test "ignores fields a caller may not set, from a device object or the top level", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      device = firmware_device_fixture(user, org, product, tmp_dir)

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      other_org_key = Fixtures.org_key_fixture(other_org, other_user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})
      other_deployment_group = Fixtures.deployment_group_fixture(other_firmware, %{user: other_user})

      for {shape, wrap} <- body_shapes() do
        params = %{
          description: "still mine, #{shape}",
          org_id: other_org.id,
          product_id: other_product.id,
          deployment_id: other_deployment_group.id,
          deployment_group_id: other_deployment_group.id,
          updates_enabled: false
        }

        conn
        |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), wrap.(params))
        |> json_response(201)

        device = Repo.reload(device)
        assert device.description == "still mine, #{shape}"
        assert device.org_id == org.id
        assert device.product_id == product.id
        assert is_nil(device.deployment_id)
        assert device.update_mode == :automatic
      end
    end

    test "updates the device in the documented example", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)
      %{"device" => fields} = example = DeviceSchemas.DeviceUpdateRequest.schema().example

      conn
      |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), example)
      |> json_response(201)

      device = Repo.reload(device)
      assert device.description == fields["description"]
      assert device.tags == fields["tags"]
      assert to_string(device.update_mode) == fields["update_mode"]
      assert device.managed_updates_allowed == fields["managed_updates_allowed"]
    end

    test "saves each documented field, from a device object or the top level", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)
      path = Routes.api_device_path(conn, :update, org.name, product.name, device.identifier)

      for {shape, wrap} <- body_shapes() do
        fields = %{
          description: "on the bench, #{shape}",
          tags: ["bench", to_string(shape)],
          update_mode: "off",
          connecting_code: "IO.puts(:#{shape})"
        }

        conn |> put(path, wrap.(fields)) |> json_response(201)

        device = Repo.reload(device)
        assert device.description == "on the bench, #{shape}"
        assert device.tags == ["bench", to_string(shape)]
        assert device.update_mode == :off
        assert device.connecting_code == "IO.puts(:#{shape})"
      end
    end

    test "allows and forbids the device managing its own updates, auditing each change", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)
      refute device.managed_updates_allowed
      path = Routes.api_device_path(conn, :update, org.name, product.name, device.identifier)

      data = conn |> put(path, %{managed_updates_allowed: true}) |> json_response(201) |> Map.fetch!("data")
      assert data["managed_updates_allowed"] == true
      assert Repo.reload(device).managed_updates_allowed

      conn |> put(path, %{device: %{managed_updates_allowed: false}}) |> json_response(201)
      refute Repo.reload(device).managed_updates_allowed

      descriptions = device |> AuditLogs.logs_for() |> Enum.map(& &1.description)
      assert "User #{user.name} allowed device-managed updates for device #{device.identifier}" in descriptions
      assert "User #{user.name} disallowed device-managed updates for device #{device.identifier}" in descriptions
    end

    test "writes no managed_updates_allowed audit entry when it doesn't change", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)
      refute device.managed_updates_allowed

      conn
      |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
        managed_updates_allowed: false
      })
      |> json_response(201)

      refute device |> AuditLogs.logs_for() |> Enum.any?(&(&1.description =~ "device-managed updates"))
    end

    test "refuses a managed_updates_allowed that isn't a boolean, and changes nothing", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)

      assert conn
             |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
               description: "changed",
               managed_updates_allowed: "sometimes"
             })
             |> json_response(422) ==
               %{"errors" => %{"detail" => ~s(managed_updates_allowed must be true or false, got "sometimes".)}}

      assert Repo.reload(device).description == device.description
      assert AuditLogs.logs_for(device) == []
    end

    test "saves the other fields only if managed_updates_allowed is saved too", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)

      expect(Updates, :set_managed_updates_allowed, fn device, true, _user ->
        changeset =
          device
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:managed_updates_allowed, "could not be saved")

        {:error, :update_with_audit, changeset, %{}}
      end)

      assert conn
             |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
               description: "changed",
               managed_updates_allowed: true
             })
             |> json_response(422) ==
               %{"errors" => %{"managed_updates_allowed" => ["could not be saved"]}}

      assert Repo.reload(device).description == device.description
      assert AuditLogs.logs_for(device) == []
    end

    test "moving to automatic clears the update attempts, audits the mode, and tells the orchestrator after the commit",
         %{conn: conn, user: user, org: org, product: product, tmp_dir: tmp_dir} do
      device =
        deployed_device_fixture(user, org, product, tmp_dir, %{
          update_mode: :off,
          update_attempts: [DateTime.truncate(DateTime.utc_now(), :second)]
        })

      # The orchestrator reads the device from the database when it is told, so
      # telling it before the commit would have it find the device still off.
      expect(DeploymentOrchestratorEvents, :device_updated, fn told ->
        refute Repo.in_transaction?()
        assert told.id == device.id
        assert told.update_mode == :automatic
        :ok
      end)

      data =
        conn
        |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
          device: %{update_mode: "automatic"}
        })
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["update_mode"] == "automatic"

      device = Repo.reload(device)
      assert device.update_mode == :automatic
      assert device.update_attempts == []

      descriptions = device |> AuditLogs.logs_for() |> Enum.map(& &1.description)
      assert "User #{user.name} set the update mode for device #{device.identifier} to automatic" in descriptions
    end

    test "moving out of automatic audits the mode and leaves the orchestrator alone", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = deployed_device_fixture(user, org, product, tmp_dir, %{update_mode: :automatic})
      reject(DeploymentOrchestratorEvents, :device_updated, 1)

      conn
      |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
        update_mode: "device_managed"
      })
      |> json_response(201)

      assert Repo.reload(device).update_mode == :device_managed

      descriptions = device |> AuditLogs.logs_for() |> Enum.map(& &1.description)
      assert "User #{user.name} set the update mode for device #{device.identifier} to device_managed" in descriptions
    end

    test "writes no update mode audit entry, and tells the orchestrator nothing, when the mode doesn't change", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = deployed_device_fixture(user, org, product, tmp_dir, %{update_mode: :automatic})
      reject(DeploymentOrchestratorEvents, :device_updated, 1)

      conn
      |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
        update_mode: "automatic"
      })
      |> json_response(201)

      refute device |> AuditLogs.logs_for() |> Enum.any?(&(&1.description =~ "update mode"))
    end

    test "refuses an update_mode that isn't a mode, and changes nothing", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = firmware_device_fixture(user, org, product, tmp_dir)
      path = Routes.api_device_path(conn, :update, org.name, product.name, device.identifier)

      assert conn |> put(path, %{description: "changed", update_mode: "sometimes"}) |> json_response(422) ==
               %{"errors" => %{"update_mode" => ["is invalid"]}}

      assert conn |> put(path, %{description: "changed", update_mode: nil}) |> json_response(422) ==
               %{"errors" => %{"update_mode" => ["can't be blank"]}}

      device = Repo.reload(device)
      assert device.description != "changed"
      assert device.update_mode == :automatic
      assert AuditLogs.logs_for(device) == []
    end

    test "saves the other fields only if the update mode is saved too", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      device = deployed_device_fixture(user, org, product, tmp_dir, %{update_mode: :off})
      reject(DeploymentOrchestratorEvents, :device_updated, 1)

      expect(Updates, :save_update_mode, fn device, :automatic, _user ->
        changeset =
          device
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:update_mode, "could not be saved")

        {:error, :update_with_audit, changeset, %{}}
      end)

      assert conn
             |> put(Routes.api_device_path(conn, :update, org.name, product.name, device.identifier), %{
               description: "changed",
               update_mode: "automatic"
             })
             |> json_response(422) ==
               %{"errors" => %{"update_mode" => ["could not be saved"]}}

      device = Repo.reload(device)
      assert device.description != "changed"
      assert device.update_mode == :off
      assert AuditLogs.logs_for(device) == []
    end
  end

  describe "authenticate devices" do
    test "valid certificate", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware)
      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      _device_certificate = Fixtures.device_certificate_fixture(device, cert)

      cert64 =
        cert
        |> X509.Certificate.to_pem()
        |> Base.encode64()

      conn =
        post(conn, Routes.api_device_path(conn, :auth, org.name, product.name), %{
          "certificate" => cert64
        })

      assert json_response(conn, 200)["data"]
    end
  end

  describe "upgrade firmware" do
    test "pushing new firmware to a device", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware_one = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_two = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      device = Fixtures.device_fixture(org, product, firmware_one)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      url = Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier)
      conn = post(conn, url, %{"uuid" => firmware_two.uuid})

      assert response(conn, 204)
      assert_broadcast("update", %{})
    end
  end

  describe "clear penalty box" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, org.name, product.name, device.identifier)
        )

      assert response(conn, 204)

      assert device.updates_blocked_until
      device = Repo.reload(device)
      refute device.updates_blocked_until
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, device.identifier)
        )

      assert response(conn, 204)

      assert device.updates_blocked_until
      device = Repo.reload(device)
      refute device.updates_blocked_until
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "reboot" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)
        )

      assert response(conn, 204)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :reboot, device.identifier))

      assert response(conn, 204)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "a member with a custom role" do
    setup %{user: user, user2: user2, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      role = Fixtures.org_role_fixture(org, %{permissions: ["device:reboot"]})
      {:ok, _} = Accounts.add_org_user(org, user2, %{org_role_id: role.id})

      %{device: device, product: product}
    end

    test "can do what the role grants, with the short url", %{conn2: conn, device: device} do
      assert response(post(conn, Routes.api_device_path(conn, :reboot, device.identifier)), 204)

      assert_error_sent(401, fn ->
        post(conn, Routes.api_device_path(conn, :reconnect, device.identifier))
      end)
    end

    test "can do what the role grants, with the nested url", %{conn2: conn, org: org, product: product, device: device} do
      assert response(
               post(conn, Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)),
               204
             )

      assert_error_sent(401, fn ->
        post(conn, Routes.api_device_path(conn, :reconnect, org.name, product.name, device.identifier))
      end)
    end

    test "can read the device", %{conn2: conn, device: device} do
      assert json_response(get(conn, Routes.api_device_path(conn, :show, device.identifier)), 200)
    end
  end

  describe "reconnect" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, org.name, product.name, device.identifier)
        )

      assert response(conn, 204)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :reconnect, device.identifier))

      assert response(conn, 204)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "code" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
          %{body: "boop"}
        )

      assert response(conn, 204)
    end

    test "support `code` being used instead of `body`", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
          %{code: "boop"}
        )

      assert response(conn, 204)
    end

    test "400 error returned when `code` or `body` are not present", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      response =
        assert_error_sent(400, fn ->
          post(
            conn,
            Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
            %{snoot: "boop"}
          )
        end)

      assert {400, [_h | _t], message} = response
      assert message =~ "code or body parameter required"
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
          %{body: "boop"}
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :code, device.identifier), %{body: "boop"})

      assert response(conn, 204)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :code, device.identifier),
          %{body: "boop"}
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "upgrade" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier),
          %{uuid: firmware.uuid}
        )

      assert response(conn, 204)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier),
          %{uuid: firmware.uuid}
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(conn, Routes.api_device_path(conn, :upgrade, device.identifier), %{
          uuid: firmware.uuid
        })

      assert response(conn, 204)
    end

    test "conflict, when the device is already updating", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      path = Routes.api_device_path(conn, :upgrade, device.identifier)

      assert response(post(conn, path, %{uuid: firmware.uuid}), 204)

      assert json_response(post(conn, path, %{uuid: firmware.uuid}), 409) == %{
               "errors" => %{
                 "detail" => "The device is already updating. Wait for that update to finish before sending another."
               }
             }
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, device.identifier),
          %{uuid: firmware.uuid}
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "move device to a new product" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )

      assert response(conn, 200)

      device = Repo.reload(device)
      assert device.org_id == org2.id
      assert device.product_id == product2.id
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error(404)

      device = Repo.reload(device)
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "failure: missing permissions in new product, with nested url",
         %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      user2 = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(user2, %{name: "org2"})
      product2 = Fixtures.product_fixture(user2, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error()
    end

    test "failure: an org that doesn't exist answers the same as one the user can't manage",
         %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => "no-such-org",
            "new_product_name" => "product2"
          }
        )
      end)
      |> assert_authorization_error()

      device = Repo.reload(device)
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "a custom role in the new org has to be able to add devices",
         %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      owner = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(owner, %{name: "org2"})
      product2 = Fixtures.product_fixture(owner, org2, %{name: "product2"})
      role = Fixtures.org_role_fixture(org2, %{permissions: ["device:update"]})
      {:ok, _} = Accounts.add_org_user(org2, user, %{org_role_id: role.id})

      move = fn ->
        post(conn, Routes.api_device_path(conn, :move, org.name, product.name, device.identifier), %{
          "new_org_name" => org2.name,
          "new_product_name" => product2.name
        })
      end

      assert_error_sent(401, move)

      {:ok, _} = Accounts.OrgRoles.update_org_role(role, %{"permissions" => ["device:create"]})

      assert json_response(move.(), 200)["data"]["product_name"] == product2.name
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )

      assert response(conn, 200)

      device = Repo.reload(device)
      assert device.org_id == org2.id
      assert device.product_id == product2.id
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error(404)

      device = Repo.reload(device)
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "failure: missing permissions in new product, with short url",
         %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      user2 = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(user2, %{name: "org2"})
      product2 = Fixtures.product_fixture(user2, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error()
    end

    test "failure: a soft-deleted device is refused with the changeset error", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      {:ok, device} = org |> Fixtures.device_fixture(product, firmware) |> Devices.delete_device()

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      conn =
        post(conn, Routes.api_device_path(conn, :move, device.identifier), %{
          "new_org_name" => org2.name,
          "new_product_name" => product2.name
        })

      assert json_response(conn, 422) == %{
               "errors" => %{"deleted_at" => ["cannot update while marked as deleted"]}
             }

      assert Repo.reload(device).org_id == org.id
    end
  end

  describe "scripts: send" do
    test "success, with nested url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_device_script_path(
          conn,
          :send,
          org.name,
          product.name,
          device.identifier,
          script.id
        )

      Runner
      |> expect(:send, fn _, _, _ -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert()
    end

    test "handles timeout param as a string or integer", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_device_script_path(
          conn,
          :send,
          org.name,
          product.name,
          device.identifier,
          script.id,
          %{"timeout" => "1000"}
        )

      Runner
      |> expect(:send, fn _, _, 1000 -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert()

      path =
        Routes.api_device_script_path(
          conn,
          :send,
          org.name,
          product.name,
          device.identifier,
          script.id,
          %{"timeout" => 1000}
        )

      Runner
      |> expect(:send, fn _, _, 1000 -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert()
    end

    test "returns 403 for timeouts", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_device_script_path(
          conn,
          :send,
          org.name,
          product.name,
          device.identifier,
          script.id
        )

      message = "device not available or responding"

      Runner
      |> expect(:send, fn _, _, _ -> {:error, message} end)

      resp =
        conn
        |> post(path)
        |> json_response(403)

      assert resp == %{"errors" => %{"detail" => message}}
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_script_path(
            conn,
            :send,
            org.name,
            product.name,
            device.identifier,
            script.id
          )
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_script_path(
          conn,
          :send,
          device.identifier,
          script.id
        )

      Runner
      |> expect(:send, fn _, _, _ -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert()
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_script_path(
            conn,
            :send,
            device.identifier,
            script.id
          )
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "devices in a deleted org" do
    setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      # Deleting the org leaves the user's admin membership in place.
      {:ok, _org} = Accounts.soft_delete_org(org)

      %{device: device, firmware: firmware, script: script}
    end

    test "can't be reached by a former member through the short url", %{
      conn: conn,
      user: user,
      org: org,
      device: device,
      firmware: firmware,
      script: script
    } do
      new_org = Fixtures.org_fixture(user, %{name: "new-org"})
      new_product = Fixtures.product_fixture(user, new_org, %{name: "new-product"})

      requests = [
        {:get, ~p"/api/devices/#{device.identifier}", %{}},
        {:post, ~p"/api/devices/#{device.identifier}/code", %{body: "boop"}},
        {:post, ~p"/api/devices/#{device.identifier}/move",
         %{new_org_name: new_org.name, new_product_name: new_product.name}},
        {:post, ~p"/api/devices/#{device.identifier}/reboot", %{}},
        {:post, ~p"/api/devices/#{device.identifier}/reconnect", %{}},
        {:post, ~p"/api/devices/#{device.identifier}/upgrade", %{uuid: firmware.uuid}},
        {:delete, ~p"/api/devices/#{device.identifier}/penalty", %{}},
        {:get, ~p"/api/devices/#{device.identifier}/scripts", %{}},
        {:post, ~p"/api/devices/#{device.identifier}/scripts/#{script.id}", %{}},
        {:get, ~p"/api/devices/#{device.identifier}/logs", %{}}
      ]

      for {method, path, params} <- requests do
        assert_error_sent(404, fn -> dispatch(conn, @endpoint, method, path, params) end)
        |> assert_authorization_error(404)
      end

      assert Repo.reload(device).org_id == org.id
    end

    test "can't be reached by a former member through the nested url", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert_error_sent(404, fn ->
        get(conn, ~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}")
      end)
    end
  end

  describe "soft-deleted devices" do
    setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      script = Fixtures.support_script_fixture(product, user)

      {:ok, device} =
        org
        |> Fixtures.device_fixture(product, firmware)
        |> Devices.delete_device()

      %{device: device, firmware: firmware, script: script}
    end

    test "refuse anything that would reach the device, on both urls", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware,
      script: script
    } do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{device.id}")
      reject(Runner, :send, 3)

      prefixes = [
        ~p"/api/devices/#{device.identifier}",
        ~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}"
      ]

      actions = [
        {:post, "/reboot", %{}},
        {:post, "/reconnect", %{}},
        {:post, "/code", %{body: "boop"}},
        {:post, "/upgrade", %{uuid: firmware.uuid}},
        {:delete, "/penalty", %{}},
        {:post, "/scripts/#{script.id}", %{}}
      ]

      for prefix <- prefixes, {method, action, params} <- actions do
        response =
          conn
          |> dispatch(@endpoint, method, prefix <> action, params)
          |> json_response(422)

        assert response == %{"errors" => %{"detail" => "Device is deleted and must be restored to use."}}
      end

      refute_receive %Broadcast{}
    end

    test "can still be shown, and restored", %{conn: conn, device: device} do
      conn = get(conn, ~p"/api/devices/#{device.identifier}")
      assert json_response(conn, 200)["data"]["deleted"] == true

      {:ok, device} = Devices.restore_device(device)

      conn = post(conn, ~p"/api/devices/#{device.identifier}/reboot")
      assert response(conn, 204)
    end
  end

  # A create or update body carries the device's fields in a "device" object,
  # or at the top level when it has none.
  defp body_shapes(), do: [top_level: & &1, device_object: &%{device: &1}]

  defp firmware_device_fixture(user, org, product, tmp_dir) do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    Fixtures.device_fixture(org, product, firmware)
  end

  # A device in a deployment group, which is what the orchestrator is told about.
  defp deployed_device_fixture(user, org, product, tmp_dir, attrs) do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, device} = Devices.update_device(device, Map.put(attrs, :deployment_id, deployment_group.id))
    device
  end
end
