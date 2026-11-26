defmodule NervesHubWeb.ApiSpecTest do
  @moduledoc """
  The published OpenAPI spec against what the server actually does: every
  documented path is routed, every example fits its schema, and real responses
  match the schemas and status codes documented for them.
  """
  use NervesHubWeb.APIConnCase, async: true
  use AssertEventually, timeout: 500, interval: 50

  import NervesHubWeb.APISpecAssertions

  alias NervesHub.Accounts
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias NervesHub.Support.RaucBundle
  alias NervesHubWeb.APISpecAssertions
  alias NervesHubWeb.Router

  @verbs [:get, :put, :post, :delete, :patch]

  test "every documented path and method is routed" do
    spec = APISpecAssertions.spec()

    unrouted =
      for {path, item} <- spec.paths,
          String.starts_with?(path, "/api/"),
          verb <- @verbs,
          Map.get(item, verb) != nil,
          method = verb |> to_string() |> String.upcase(),
          not routed?(method, path) do
        "#{method} #{path}"
      end

    assert unrouted == [], "The spec documents routes the router doesn't have:\n" <> Enum.join(unrouted, "\n")
  end

  test "every schema example conforms to its schema" do
    spec = APISpecAssertions.spec()

    failures =
      for {title, schema} <- spec.components.schemas,
          schema.example != nil,
          {:error, errors} <- [OpenApiSpex.cast_value(schema.example, schema, spec)] do
        "#{title}: " <> Enum.map_join(errors, "; ", &to_string/1)
      end

    assert failures == [], "Examples that don't fit their schema:\n" <> Enum.join(Enum.sort(failures), "\n")
  end

  # The spec keys schemas by title, so a second schema with a title already
  # taken silently replaces the first wherever either is used.
  test "every schema has a title of its own" do
    {:ok, modules} = :application.get_key(:nerves_hub, :modules)

    duplicates =
      modules
      |> Enum.filter(&(String.starts_with?(inspect(&1), "NervesHubWeb.API.") and schema_module?(&1)))
      |> Enum.group_by(& &1.schema().title)
      |> Enum.filter(fn {_title, modules} -> length(modules) > 1 end)

    assert duplicates == [], "Schemas sharing a title: #{inspect(duplicates)}"
  end

  defp schema_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :schema, 0)

  # Fills each `{param}` with its own name, and checks the router sends that
  # path to the route the spec names.
  defp routed?(method, path) do
    sample = Regex.replace(~r/\{(\w+)\}/, path, "\\1")

    case Phoenix.Router.route_info(Router, method, sample, "localhost") do
      %{route: route} -> spec_path(route) == path
      :error -> false
    end
  end

  describe "devices" do
    setup %{org: org, product: product, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      connected =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["prod", "beta"], deployment_id: deployment_group.id})

      Fixtures.device_connection_fixture(connected)
      never_seen = Fixtures.device_fixture(org, product, firmware)

      %{connected: connected, never_seen: never_seen, firmware: firmware}
    end

    test "list", %{conn: conn, org: org, product: product} do
      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/devices")
      |> assert_documented_response()
    end

    test "show a connected device in a deployment group", %{conn: conn, connected: device} do
      data =
        conn
        |> get(~p"/api/devices/#{device.identifier}")
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"online" => "connected", "connection_status" => "connected", "tags" => ["prod", "beta"]} = data
      assert %{"deployment_group" => %{}, "deleted" => false} = data
    end

    test "show a device that has never connected", %{conn: conn, org: org, product: product, never_seen: device} do
      data =
        conn
        |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}")
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"online" => "not_seen", "connection_status" => "not_seen", "last_communication" => "never"} = data
    end

    test "show a device that is still connecting", %{conn: conn, org: org, product: product} = context do
      device = Fixtures.device_fixture(org, product, context.firmware)
      Fixtures.device_connection_fixture(device, %{status: :connecting})

      data =
        conn
        |> get(~p"/api/devices/#{device.identifier}")
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"online" => "connecting", "connection_status" => "connecting"} = data
    end

    test "create", %{conn: conn, org: org, product: product} do
      conn
      |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/devices", %{identifier: "spec-device"})
      |> assert_documented_response(absent: ["data.shared_secret"])
      |> json_response(201)
    end

    test "create with a shared secret", %{conn: conn, org: org, product: product} do
      conn
      |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/devices", %{
        identifier: "spec-device",
        shared_secret: true
      })
      |> assert_documented_response()
      |> json_response(201)
    end

    test "update answers 201", %{conn: conn, org: org, product: product, connected: device} do
      conn
      |> put(~p"/api/orgs/#{org.name}/products/#{product.name}/devices/#{device.identifier}", %{
        device: %{description: "updated"}
      })
      |> assert_documented_response()
      |> json_response(201)
    end

    test "bulk import answers 201 with no body", %{conn: conn, org: org, product: product} do
      manifest = File.read!("test/fixtures/devices_bulk_create/microchip_trust_and_go_manifest.json")

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/devices/import", manifest)
      |> assert_documented_response()
      |> response(201)

      # The import carries on after the response; let it finish before the
      # sandbox is checked back in.
      eventually assert Repo.aggregate(Notification, :count) == 1
    end
  end

  describe "products" do
    test "create reads a top-level name", %{conn: conn, org: org} do
      data =
        conn
        |> post(~p"/api/orgs/#{org.name}/products", %{name: "SpecProduct"})
        |> assert_documented_response()
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["name"] == "SpecProduct"
    end

    test "show", %{conn: conn, org: org, product: product} do
      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}")
      |> assert_documented_response()
    end

    test "utilization", %{conn: conn, org: org, product: product} do
      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/utilization")
      |> assert_documented_response()
    end
  end

  describe "users" do
    setup do
      password = "spec-password-1234"
      %{user: Fixtures.user_fixture(%{password: password}), password: password}
    end

    test "auth returns the user and a token", %{user: user, password: password} do
      data =
        build_conn()
        |> post(~p"/api/users/auth", %{email: user.email, password: password})
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert "nhu_" <> _ = data["token"]
    end

    test "login returns the user and a token", %{user: user, password: password} do
      build_conn()
      |> post(~p"/api/users/login", %{email: user.email, password: password})
      |> assert_documented_response()
    end

    test "me", %{user: user} do
      user
      |> Accounts.create_user_api_token("spec")
      |> build_auth_conn()
      |> get(~p"/api/users/me")
      |> assert_documented_response()
    end
  end

  describe "support scripts" do
    test "create answers 200", %{conn: conn, org: org, product: product} do
      data =
        conn
        |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/scripts", %{
          name: "Spec",
          text: "IO.puts(:ok)",
          tags: "one,two"
        })
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{"id" => id, "tags" => ["one", "two"]} = data
      assert is_integer(id)
    end

    test "show and list", %{conn: conn, org: org, product: product, user: user} do
      script = Fixtures.support_script_fixture(product, user, %{tags: "cleanup"})

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/scripts/#{script.id}")
      |> assert_documented_response()

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/scripts")
      |> assert_documented_response()
    end
  end

  describe "firmware, archives and deployment groups" do
    setup %{org: org, user: user, tmp_dir: tmp_dir} do
      %{org_key: Fixtures.org_key_fixture(org, user, tmp_dir)}
    end

    test "firmware upload, show and list", %{conn: conn, org: org, product: product, org_key: org_key, tmp_dir: dir} do
      path = Fixtures.firmware_file_fixture(org_key, product, %{dir: dir})
      upload = %Plug.Upload{path: path, filename: "spec.fw", content_type: "application/octet-stream"}

      %{"uuid" => uuid} =
        conn
        |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/firmwares", %{firmware: upload})
        |> assert_documented_response()
        |> json_response(201)
        |> Map.fetch!("data")

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/firmwares/#{uuid}")
      |> assert_documented_response()

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/firmwares")
      |> assert_documented_response()
    end

    test "archive upload and show", %{conn: conn, org: org, product: product, org_key: org_key, tmp_dir: dir} do
      path = Fixtures.archive_file_fixture(org_key, product, %{dir: dir})
      upload = %Plug.Upload{path: path, filename: "spec.fw", content_type: "application/octet-stream"}

      %{"uuid" => uuid} =
        conn
        |> post(~p"/api/orgs/#{org.name}/products/#{product.name}/archives", %{archive: upload})
        |> assert_documented_response()
        |> json_response(201)
        |> Map.fetch!("data")

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/archives/#{uuid}")
      |> assert_documented_response()
    end

    test "deployment group show and list", %{conn: conn, org: org, product: product, user: user} = context do
      firmware = Fixtures.firmware_fixture(context.org_key, product, %{dir: context.tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      data =
        conn
        |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/deployments/#{deployment_group.name}")
        |> assert_documented_response()
        |> json_response(200)
        |> Map.fetch!("data")

      assert Map.has_key?(data, "archive_uuid")

      conn
      |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/deployments")
      |> assert_documented_response()
    end

    test "deployment group releases list, show, create and update",
         %{conn: conn, org: org, product: product} = context do
      firmware = Fixtures.firmware_fixture(context.org_key, product, %{dir: context.tmp_dir})
      next_firmware = Fixtures.firmware_fixture(context.org_key, product, %{version: "1.0.1", dir: context.tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: context.user})
      releases = ~p"/api/orgs/#{org.name}/products/#{product.name}/deployments/#{deployment_group.name}/releases"

      conn |> get(releases) |> assert_documented_response()
      conn |> get(releases <> "/1") |> assert_documented_response()
      conn |> get(releases <> "/9") |> assert_documented_response()

      data =
        conn
        |> post(releases, %{firmware: next_firmware.uuid, description: "Spec"})
        |> assert_documented_response()
        |> json_response(201)
        |> Map.fetch!("data")

      assert %{"number" => 2, "is_current" => true} = data

      conn |> post(releases, %{firmware: next_firmware.uuid}) |> assert_documented_response()

      conn
      |> patch(releases <> "/2", %{required: true, connecting_code_mode: "first"})
      |> assert_documented_response()
    end
  end

  describe "signing keys" do
    test "create an x509_certificate key, and list", %{conn: conn, org: org} do
      %{certificate: certificate} = RaucBundle.keypair()

      data =
        conn
        |> post(~p"/api/orgs/#{org.name}/keys", %{name: "rauc", key: certificate, scheme: "x509_certificate"})
        |> assert_documented_response()
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["scheme"] == "x509_certificate"

      conn
      |> get(~p"/api/orgs/#{org.name}/keys")
      |> assert_documented_response()
    end
  end

  describe "CA certificates" do
    test "show and list, with and without JITP", %{conn: conn, org: org, product: product} do
      %{db_cert: plain} = Fixtures.ca_certificate_fixture(org)
      %{db_cert: with_jitp} = Fixtures.ca_certificate_fixture(org)

      {:ok, _} =
        with_jitp
        |> Repo.preload(:jitp)
        |> CACertificates.update_ca_certificate(%{jitp: %{product_id: product.id, tags: ["prod"], description: "JITP"}})

      for serial <- [plain.serial, with_jitp.serial] do
        conn
        |> get(~p"/api/orgs/#{org.name}/ca_certificates/#{serial}")
        |> assert_documented_response()
      end

      conn
      |> get(~p"/api/orgs/#{org.name}/ca_certificates")
      |> assert_documented_response()
    end
  end
end
