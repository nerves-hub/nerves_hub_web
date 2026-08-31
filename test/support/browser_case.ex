defmodule NervesHubWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  alias NervesHub.Fixtures
  alias NervesHub.Support.Fwup
  alias NervesHubWeb.ConnCase
  alias Plug.Test

  defmacro __using__(opts) do
    quote do
      use DefaultMocks
      use ConnCase, unquote(opts)

      import Phoenix.LiveViewTest
      import PhoenixTest
      import Test

      @moduletag :tmp_dir

      # Generate the fwup key pair and a signed firmware file once per test
      # module. The key pair and fw file are reused by every test in the module
      # (each test creates a fresh org/product so there are no uniqueness
      # conflicts). This eliminates three fwup subprocess calls per test.
      setup_all do
        fwup_dir =
          Path.join(System.tmp_dir!(), "browser_case_#{System.unique_integer([:positive])}")

        File.mkdir_p!(fwup_dir)
        key_name = "browser_key_#{System.unique_integer([:positive])}"
        Fwup.gen_key_pair(key_name, fwup_dir)
        {:ok, fw_path} = Fwup.create_signed_firmware(key_name, "unsigned", "signed", %{dir: fwup_dir, product: "Hop"})

        on_exit(fn -> File.rm_rf!(fwup_dir) end)

        {:ok, %{fwup_dir: fwup_dir, fwup_key_name: key_name, fw_path: fw_path}}
      end

      setup context do
        %{fwup_dir: fwup_dir, fwup_key_name: fwup_key_name, fw_path: fw_path, tmp_dir: tmp_dir} = context

        # Copy the cached key pair into this test's tmp_dir so that any test
        # that calls firmware_fixture(org_key, product, %{dir: tmp_dir}) finds
        # the private key where fwup expects it.
        File.cp!(Path.join(fwup_dir, fwup_key_name <> ".pub"), Path.join(tmp_dir, fwup_key_name <> ".pub"))
        File.cp!(Path.join(fwup_dir, fwup_key_name <> ".priv"), Path.join(tmp_dir, fwup_key_name <> ".priv"))

        user_name = "Jeff"
        user = Fixtures.user_fixture(%{name: user_name})
        org = Fixtures.org_fixture(user, %{name: user_name})
        product = Fixtures.product_fixture(user, org, %{name: "Hop"})
        org_key = Fixtures.org_key_fixture_from_existing(org, user, fwup_key_name, fwup_dir)
        firmware = Fixtures.firmware_fixture_from_file(org, fw_path)
        deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
        device = Fixtures.device_fixture(org, product, firmware)
        %{db_cert: device_certificate} = Fixtures.device_certificate_fixture(device)

        fixture = %{
          org: org,
          device: device,
          device_certificate: device_certificate,
          org_key: org_key,
          user: user,
          firmware: firmware,
          deployment_group: deployment_group,
          product: product
        }

        token = NervesHub.Accounts.create_user_session_token(user)

        conn =
          build_conn()
          |> init_test_session(%{
            "user_token" => token
          })

        %{
          conn: conn,
          user: user,
          org: org,
          firmware: firmware,
          fixture: fixture,
          org_key: org_key,
          product: product,
          device: device,
          deployment_group: deployment_group
        }
      end
    end
  end
end
