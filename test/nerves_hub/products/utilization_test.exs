defmodule NervesHub.Products.UtilizationTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query, only: [where: 2]

  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceLatestMetrics
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.Utilization
  alias NervesHub.Repo
  alias NervesHub.Webhooks
  alias X509.Certificate.Template
  alias X509.Certificate.Validity

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    # Every extension off, as a product made through the API starts.
    product = Fixtures.product_fixture(user, org, %{extensions: %{}})
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    %{user: user, org: org, product: product, org_key: org_key}
  end

  defp item(report, key), do: Enum.find(report.items, &(&1.key == key))

  defp status(product, key), do: product |> Utilization.report() |> item(key) |> Map.fetch!(:status)

  defp firmware(%{org_key: org_key, product: product, tmp_dir: dir}, params \\ %{}) do
    Fixtures.firmware_fixture(org_key, product, Map.put(params, :dir, dir))
  end

  defp connected_device(context, params \\ %{}) do
    Fixtures.device_fixture(context.org, context.product, firmware(context), Map.put(params, :status, :provisioned))
  end

  defp methods(product) do
    Map.new(Utilization.report(product).device_auth, &{&1.key, &1.devices})
  end

  # A certificate as `ATECC508A.Certificate.new_device/5` builds one: a
  # 128-bit serial number with `01` as its top bits, and validity on the hour.
  defp nerves_key_certificate(identifier) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "/CN=Signer", template: :root_ca)
    key = X509.PrivateKey.new_ec(:secp256r1)

    <<serial::128>> = <<0b01::2, :crypto.strong_rand_bytes(16)::bitstring-size(126)>>
    not_before = %{DateTime.utc_now() | minute: 0, second: 0, microsecond: {0, 0}}
    not_after = %{not_before | year: not_before.year + 31}

    X509.Certificate.new(X509.PublicKey.derive(key), "/CN=#{identifier}", ca, ca_key,
      template: %Template{
        serial: serial,
        validity: Validity.new(not_before, not_after),
        hash: :sha256,
        extensions: [subject_key_identifier: true, authority_key_identifier: true]
      }
    )
  end

  describe "report/1" do
    test "a new product has every item, none of them done", %{product: product} do
      report = Utilization.report(product)

      assert report.score == %{done: 0, total: 13}
      assert Enum.count(report.items, &(&1.group == :authentication)) == 1
      assert Enum.count(report.items, &(&1.group == :recommended)) == 12
      assert Enum.any?(report.items, &(&1.group == :optional))
      assert Enum.all?(report.items, &(&1.status == :todo))

      assert Enum.map(report.device_auth, &{&1.key, &1.label, &1.level, &1.devices}) == [
               {"shared_secret", "Shared Secret", :warning, 0},
               {"local_cert", "LocalCert", :good, 0},
               {"nerves_key", "NervesKey", :good, 0}
             ]

      for item <- report.items do
        assert "https://docs.nerves-hub.org/" <> _ = item.docs_url
        assert item.title != "" and item.description != "" and item.summary != ""
      end
    end

    test "item keys are unique", %{product: product} do
      keys = Enum.map(Utilization.report(product).items, & &1.key)

      assert keys == Enum.uniq(keys)
    end

    test "optional items never count towards the score", %{product: product, user: user} do
      Fixtures.support_script_fixture(product, user)

      report = Utilization.report(product)

      assert item(report, "support_scripts").status == :done
      assert report.score == %{done: 0, total: 13}
    end

    test "score/1 is the report's score", %{product: product, user: user} do
      Fixtures.api_key_fixture(product, user)

      assert Utilization.score(product) == %{done: 1, total: 13}
      assert Utilization.score(product) == Utilization.report(product).score
    end
  end

  describe "device authentication" do
    test "a device that connected without a certificate used a shared secret", context do
      connected_device(context)

      report = Utilization.report(context.product)
      auth = item(report, "device_auth")

      assert methods(context.product) == %{"shared_secret" => 1, "local_cert" => 0, "nerves_key" => 0}
      assert auth.status == :attention
      assert auth.summary == "1 of 1 device connects with a secret shared by the whole product."
    end

    test "a device that has never connected and has no certificate isn't counted", context do
      Fixtures.device_fixture(context.org, context.product, firmware(context))

      assert methods(context.product) == %{"shared_secret" => 0, "local_cert" => 0, "nerves_key" => 0}
      assert status(context.product, "device_auth") == :todo
    end

    test "an ordinary certificate is LocalCert", context do
      device = connected_device(context)
      Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))

      assert methods(context.product) == %{"shared_secret" => 0, "local_cert" => 1, "nerves_key" => 0}

      auth = context.product |> Utilization.report() |> item("device_auth")
      assert auth.status == :done
      assert auth.summary == "The 1 device with a certificate."
    end

    test "a certificate with the ATECC508A's shape is NervesKey", context do
      device = connected_device(context)
      Fixtures.device_certificate_fixture(device, nerves_key_certificate(device.identifier))

      assert methods(context.product) == %{"shared_secret" => 0, "local_cert" => 0, "nerves_key" => 1}
      assert status(context.product, "device_auth") == :done
    end

    test "a device is counted once, as NervesKey if any of its certificates is", context do
      device = connected_device(context)
      Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))
      Fixtures.device_certificate_fixture(device, nerves_key_certificate(device.identifier))

      assert methods(context.product) == %{"shared_secret" => 0, "local_cert" => 0, "nerves_key" => 1}
    end

    test "any shared secret device keeps it from done", context do
      connected_device(context)
      device = connected_device(context)
      Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))

      assert methods(context.product) == %{"shared_secret" => 1, "local_cert" => 1, "nerves_key" => 0}
      assert status(context.product, "device_auth") == :attention
    end

    test "an active product shared secret keeps it from done", context do
      device = connected_device(context)
      Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))
      {:ok, secret} = Products.create_shared_secret_auth(context.product)

      auth = context.product |> Utilization.report() |> item("device_auth")
      assert auth.status == :attention
      assert auth.summary =~ "1 product shared secret can still be used"

      {:ok, _} = Products.deactivate_shared_secret_auth(context.product, secret.id)

      assert status(context.product, "device_auth") == :done
    end

    test "a device with a secret of its own isn't a warning", context do
      device = connected_device(context)
      {:ok, secret} = Devices.create_shared_secret_auth(device)

      report = Utilization.report(context.product)
      assert [%{key: "shared_secret", level: :good, devices: 1} | _] = report.device_auth
      assert %{status: :done, summary: "The 1 device with a secret of its own."} = item(report, "device_auth")

      # The product's secret is how such a device enrols, so it doesn't warn.
      {:ok, _} = Products.create_shared_secret_auth(context.product)
      assert status(context.product, "device_auth") == :done

      # Another device on the product's secret does.
      connected_device(context)
      report = Utilization.report(context.product)
      assert [%{key: "shared_secret", level: :warning, devices: 2} | _] = report.device_auth
      assert %{status: :attention, summary: summary} = item(report, "device_auth")
      assert summary =~ "1 of 2 devices connects with a secret shared by the whole product."

      # A deactivated secret no longer counts as the device's own.
      {:ok, _} = Devices.deactivate_shared_secret_auth(device, secret.key, context.user)
      assert %{summary: summary} = context.product |> Utilization.report() |> item("device_auth")
      assert summary =~ "2 of 2 devices connect with a secret shared by the whole product."
    end

    test "another product's devices aren't counted", context do
      other = Fixtures.product_fixture(context.user, context.org)
      other_firmware = Fixtures.firmware_fixture(context.org_key, other, %{dir: context.tmp_dir})
      Fixtures.device_fixture(context.org, other, other_firmware, %{status: :provisioned})

      assert methods(context.product) == %{"shared_secret" => 0, "local_cert" => 0, "nerves_key" => 0}
    end
  end

  describe "recommended items" do
    test "signed firmware is done once firmware is uploaded", context do
      assert status(context.product, "signed_firmware") == :todo

      firmware(context)

      assert status(context.product, "signed_firmware") == :done
    end

    test "an unsigned ESP-IDF image doesn't count as signed firmware", context do
      firmware = firmware(context)
      Repo.update_all(where(Firmware, id: ^firmware.id), set: [org_key_id: nil, tool: "esp-idf"])

      assert %{status: :todo, summary: "1 firmware uploaded, none of them signed."} =
               context.product |> Utilization.report() |> item("signed_firmware")
    end

    test "the organization's own items can be left out, and aren't scored then", context do
      report = Utilization.report(context.product, organization: false)

      refute item(report, "two_factor")
      refute item(report, "custom_roles")
      assert report.score.total == Utilization.report(context.product).score.total - 1
    end

    test "deployment groups need one turned on", context do
      Fixtures.deployment_group_fixture(firmware(context), %{name: "off", user: context.user})

      # Not in use yet, which is nothing to warn about.
      assert status(context.product, "deployments") == :todo
      assert status(context.product, "delta_updates") == :todo

      Fixtures.deployment_group_fixture(firmware(context), %{name: "on", is_active: true, user: context.user})

      assert status(context.product, "deployments") == :done
    end

    test "delta updates need firmware that can be sent as a delta", context do
      group =
        Fixtures.deployment_group_fixture(firmware(context), %{
          is_active: true,
          delta_updatable: true,
          user: context.user
        })

      assert status(context.product, "delta_updates") == :attention

      group
      |> Repo.preload(current_release: :firmware)
      |> then(& &1.current_release.firmware)
      |> Ecto.Changeset.change(delta_updatable: true)
      |> Repo.update!()

      assert status(context.product, "delta_updates") == :done

      group |> Ecto.Changeset.change(delta_updatable: false) |> Repo.update!()

      assert status(context.product, "delta_updates") == :todo
    end

    test "the client library is done when every connected device names one", context do
      assert status(context.product, "client_library") == :todo

      named = connected_device(context)

      Fixtures.device_connection_fixture(named, %{
        product_id: context.product.id,
        lib: "nerves_hub_link",
        lib_version: "2.14.0"
      })

      assert status(context.product, "client_library") == :done

      unnamed = connected_device(context)
      Fixtures.device_connection_fixture(unnamed, %{product_id: context.product.id})

      report = Utilization.report(context.product)
      assert item(report, "client_library").status == :todo
      assert item(report, "client_library").summary =~ "1 of 2 devices named a client library"
    end

    test "health needs the extension on and a report", context do
      assert status(context.product, "health") == :todo

      {:ok, _} = Products.enable_extension_setting(context.product, "health")
      product = Repo.reload!(context.product)

      assert status(product, "health") == :attention

      device = connected_device(context)

      Repo.insert!(%DeviceLatestMetrics{
        device_id: device.id,
        product_id: product.id,
        metrics: %{"cpu_temp" => 40.0},
        reported_at: DateTime.utc_now()
      })

      assert status(product, "health") == :done
    end

    test "geo needs the extension on and a location", context do
      {:ok, _} = Products.enable_extension_setting(context.product, "geo")
      product = Repo.reload!(context.product)

      assert status(product, "geo") == :attention

      device = connected_device(context)

      Fixtures.device_connection_fixture(device, %{
        product_id: product.id,
        metadata: %{"location" => %{"latitude" => 57.1, "longitude" => 12.2}}
      })

      assert status(product, "geo") == :done
    end

    test "logging that is on with no log lines is a warning", context do
      assert status(context.product, "logging") == :todo

      {:ok, _} = Products.enable_extension_setting(context.product, "logging")

      assert status(Repo.reload!(context.product), "logging") == :attention
    end

    test "error reports are done once on, since a fleet without errors is quiet", context do
      assert status(context.product, "error_reports") == :todo

      {:ok, _} = Products.enable_extension_setting(context.product, "error_reports")

      report = Utilization.report(Repo.reload!(context.product))
      assert item(report, "error_reports").status == :done
      assert item(report, "error_reports").summary =~ "No device has reported an error"
    end

    test "nothing unused is a warning", context do
      # Everything a product can have without using it: groups that are off,
      # a product shared secret, extensions nobody switched on.
      Fixtures.deployment_group_fixture(firmware(context), %{user: context.user})
      {:ok, _} = Products.create_shared_secret_auth(context.product)

      report = Utilization.report(context.product)

      assert Enum.filter(report.items, &(&1.status == :attention)) == []
    end

    test "firmware validation is done once a device reports it", context do
      connected_device(context, %{firmware_validation_status: :not_validated})

      assert status(context.product, "firmware_validation") == :todo

      connected_device(context, %{firmware_validation_status: :validated})

      assert status(context.product, "firmware_validation") == :done
    end

    test "an API key counts while it is active", %{product: product, user: user} do
      api_key = Fixtures.api_key_fixture(product, user)

      assert status(product, "ci_api_key") == :done

      {:ok, _} = Products.ApiKeys.deactivate(product, user, api_key.id)

      assert status(product, "ci_api_key") == :todo
    end

    test "notifications are done when an integration hears the product", %{product: product, org: org, user: user} do
      other = Fixtures.product_fixture(user, org)

      {:ok, _elsewhere} =
        Webhooks.create_webhook(%Scope{org: org, user: user}, %{
          "url" => "https://hooks.example.com/other",
          "events" => ["device.connected"],
          "products" => [other.name]
        })

      assert status(product, "notifications") == :todo

      {:ok, _} =
        Webhooks.create_webhook(%Scope{org: org, user: user}, %{
          "url" => "https://hooks.example.com/nerves",
          "events" => ["device.connected"]
        })

      report = Utilization.report(product)
      assert item(report, "notifications").status == :done
      assert item(report, "notifications").summary == "Events go to a webhook."
    end

    test "two-factor is done when the organization requires it", %{product: product, org: org} do
      assert status(product, "two_factor") == :todo

      org |> Ecto.Changeset.change(require_two_factor: true) |> Repo.update!()

      assert status(product, "two_factor") == :done
    end
  end

  describe "optional items" do
    test "are found from the product, its groups and its organization", context do
      %{product: product, org: org, user: user} = context

      Fixtures.org_role_fixture(org)
      Fixtures.archive_fixture(context.org_key, product, %{dir: context.tmp_dir})
      connected_device(context, %{update_mode: :device_managed, connecting_code: "IO.puts(:hi)"})

      firmware(context)
      |> Fixtures.deployment_group_fixture(%{is_active: true, user: user})
      |> Ecto.Changeset.change(priority_queue_enabled: true, workflow_definition: %{"steps" => []})
      |> Repo.update!()

      # Straight to the column: whether RAUC can be chosen depends on the instance.
      product = product |> Ecto.Changeset.change(allowed_update_tools: ["fwup", "rauc"]) |> Repo.update!()
      {:ok, _} = Products.enable_extension_setting(product, "local_shell")
      product = Repo.reload!(product)

      report = Utilization.report(product)

      for key <-
            ~w(custom_roles archives device_managed_updates connecting_code priority_queue deployment_workflow local_shell other_firmware_formats) do
        assert item(report, key).status == :done, "expected #{key} to be done"
      end

      assert item(report, "jitp").status == :todo
      assert item(report, "network_identity").status == :todo
      assert item(report, "platform_health_profiles").status == :todo
    end
  end
end

defmodule NervesHub.Products.UtilizationInstanceTest do
  # Changes the application environment and writes to ClickHouse, so it can't
  # run beside other tests.
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines
  alias NervesHub.Fixtures
  alias NervesHub.Products.Utilization

  setup do
    enabled = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, enabled) end)

    user = Fixtures.user_fixture()
    product = Fixtures.product_fixture(user, Fixtures.org_fixture(user))

    %{product: product, device_info: %DeviceInfo{device_id: 1, product_id: product.id}}
  end

  test "logging is done once a device's log lines are stored", %{product: product, device_info: device_info} do
    assert Enum.find(Utilization.report(product).items, &(&1.key == "logging")).status == :attention

    {:ok, _} =
      LogLines.async_create(device_info, %{"timestamp" => DateTime.utc_now(), "level" => "info", "message" => "up"})

    :ok = Buffer.flush(LogLine)

    logging = Enum.find(Utilization.report(product).items, &(&1.key == "logging"))
    assert logging.status == :done
    assert logging.summary == "Devices are sending their logs."
  end

  test "what the instance can't offer is unavailable and left out of the score", %{product: product} do
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    report = Utilization.report(product)
    statuses = Map.new(report.items, &{&1.key, &1.status})

    assert statuses["logging"] == :unavailable
    assert statuses["error_reports"] == :unavailable
    assert report.score == %{done: 0, total: 11}
  end
end
