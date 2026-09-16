defmodule NervesHub.ManagedDeployments.ReleaseConnectingCodeTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{connecting_code: "group"}, user)

    %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      next_firmware: next_firmware,
      deployment_group: deployment_group
    }
  end

  defp add_release(%{deployment_group: deployment_group, user: user}, firmware, params) do
    {:ok, {release, _deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, firmware, nil, user, params)

    release
  end

  defp device_on(%{org: org, product: product, deployment_group: deployment_group}, firmware) do
    Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id, connecting_code: "device"})
  end

  defp connecting_code(device), do: DeviceLink.fetch_connecting_code(%DeviceInfo{device_id: device.id})

  describe "the code a device runs when it connects" do
    test "runs a release's code after the group's by default, and the device's own last", context do
      _ = add_release(context, context.next_firmware, %{connecting_code: "release"})

      assert connecting_code(device_on(context, context.next_firmware)) == ["group", "release", "device"]
    end

    test "can run a release's code before the group's", context do
      _ = add_release(context, context.next_firmware, %{connecting_code: "release", connecting_code_mode: "first"})

      assert connecting_code(device_on(context, context.next_firmware)) == ["release", "group", "device"]
    end

    test "can override the group's code with a release's", context do
      _ = add_release(context, context.next_firmware, %{connecting_code: "release", connecting_code_mode: "override"})

      assert connecting_code(device_on(context, context.next_firmware)) == ["release", "device"]
    end

    test "comes from the release the device is running", context do
      _ = add_release(context, context.next_firmware, %{connecting_code: "release"})

      assert connecting_code(device_on(context, context.next_firmware)) == ["group", "release", "device"]
      assert connecting_code(device_on(context, context.firmware)) == ["group", "device"]

      {:ok, device_on_unknown_firmware} =
        context
        |> device_on(context.firmware)
        |> Devices.update_firmware_metadata(%{uuid: Ecto.UUID.generate(), version: "3.0.0"}, :unknown, false)

      assert connecting_code(device_on_unknown_firmware) == ["group", "device"]
    end

    test "leaves the group's code alone when the release has none, whatever its mode", context do
      _ = add_release(context, context.next_firmware, %{connecting_code: "  ", connecting_code_mode: "override"})

      assert connecting_code(device_on(context, context.next_firmware)) == ["group", "device"]
    end

    test "ignores a release's code that is only whitespace, however the row was written", context do
      release = add_release(context, context.firmware, %{connecting_code: "release", connecting_code_mode: "override"})

      # Casting treats blank code as no code, so this is the only way to hold
      # whitespace -- an `insert_all` or a changeset that doesn't cast would too
      {:ok, _} = release |> Ecto.Changeset.change(connecting_code: " \n\t ") |> Repo.update()

      assert connecting_code(device_on(context, context.firmware)) == ["group", "device"]
    end

    test "keeps the whitespace inside code that has something in it", context do
      _ = add_release(context, context.firmware, %{connecting_code: "  release\n  more\n"})

      assert connecting_code(device_on(context, context.firmware)) == ["group", "  release\n  more\n", "device"]
    end

    test "reads the device, group and release code in one query, the mode as an atom", context do
      _ = add_release(context, context.firmware, %{connecting_code: "release", connecting_code_mode: "first"})
      device = device_on(context, context.firmware)

      assert %{device: "device", deployment_group: "group", release: "release", release_mode: :first} =
               Devices.fetch_connecting_code(device.id)
    end
  end

  describe "update_deployment_release_connecting_code/3" do
    test "changes the code devices get next time they connect, and audits it", context do
      release = add_release(context, context.next_firmware, %{connecting_code: "release"})
      device = device_on(context, context.next_firmware)

      assert {:ok, release} =
               ManagedDeployments.update_deployment_release_connecting_code(
                 release,
                 %{"connecting_code" => "changed", "connecting_code_mode" => "first"},
                 context.user
               )

      assert release.connecting_code_mode == :first
      assert connecting_code(device) == ["changed", "group", "device"]

      assert [audit_log | _] = AuditLogs.logs_for(context.deployment_group)
      assert audit_log.description =~ "changed the connecting code for release #{release.number}"
    end

    test "refuses a run order it doesn't know", context do
      release = add_release(context, context.next_firmware, %{connecting_code: "release"})

      assert {:error, changeset} =
               ManagedDeployments.update_deployment_release_connecting_code(
                 release,
                 %{"connecting_code_mode" => "sometimes"},
                 context.user
               )

      assert {"is invalid", _} = changeset.errors[:connecting_code_mode]
    end
  end
end
