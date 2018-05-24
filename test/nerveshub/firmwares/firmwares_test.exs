defmodule NervesHub.FirmwaresTest do
  use NervesHub.DataCase

  alias NervesHub.Repo
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Accounts.Tenant
  alias NervesHub.Devices.Device
  alias Ecto.Changeset

  setup do
    tenant =
      %Tenant{name: "Test Tenant"}
      |> Repo.insert!()

    firmware =
      %Firmware{
        tenant_id: tenant.id,
        version: "1.0.0",
        product: "test_product",
        architecture: "arm",
        platform: "rpi0",
        upload_metadata: %{"public_url" => "http://example.com"},
        timestamp: DateTime.utc_now(),
        signed: true,
        metadata: ""
      }
      |> Repo.insert!()

    deployment =
      %Deployment{
        tenant_id: tenant.id,
        firmware_id: firmware.id,
        name: "Test Deployment",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: true
      }
      |> Repo.insert!()

    device = %Device{
      tenant_id: tenant.id,
      architecture: firmware.architecture,
      platform: firmware.platform,
      tags: deployment.conditions["tags"]
    }

    {:ok,
     %{
       tenant: tenant,
       firmware: firmware,
       deployment: deployment,
       matching_device: device
     }}
  end

  def update_version_condition(%Deployment{} = deployment, version) when is_binary(version) do
    deployment
    |> Changeset.change(%{
      conditions: %{
        "tags" => deployment.conditions["tags"],
        "version" => version
      }
    })
    |> Repo.update!()
  end

  describe "NervesHub.Firmwares.get_eligible_firmware_update/2" do
    test "returns a Firmware struct when a deployment is found where the version is eligible and whose firmware has matching architecture and platform",
         %{matching_device: device} do
      version = Version.parse!("0.5.0")

      {:ok, %Firmware{}} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns the correct Firmware struct", %{firmware: firmware, matching_device: device} do
      version = Version.parse!("0.5.0")
      firmware_id = firmware.id

      {:ok, %Firmware{id: ^firmware_id}} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} if everything matches except the architecture", %{
      matching_device: device
    } do
      device = %{device | architecture: "unmatching_architecture"}
      version = Version.parse!("0.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} if everything matches except the platform", %{
      matching_device: device
    } do
      device = %{device | platform: "unmatching_platform"}
      version = Version.parse!("0.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} if everything matches except the device does not have every tag in the deployment's tags condition",
         %{matching_device: device} do
      device = %{device | tags: ["beta"]}
      version = Version.parse!("0.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} if everything matches except the (otherwise matching) deployment has is_active set to false",
         %{deployment: deployment, matching_device: device} do
      deployment
      |> Changeset.change(%{is_active: false})
      |> Repo.update!()

      version = Version.parse!("0.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} if everything matches, except the given version does not match the deployment's version condition",
         %{matching_device: device} do
      version = Version.parse!("1.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "does not return an otherwise matching Firmware if the firmware's tenant does not match the device's",
         %{tenant: tenant, matching_device: device} do
      device = %{device | tenant_id: tenant.id + 1}
      version = Version.parse!("0.5.0")

      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, :none} properly with complex/compound version conditions", %{
      deployment: deployment,
      matching_device: device
    } do
      version = Version.parse!("0.5.0")

      deployment = update_version_condition(deployment, "~> 0.6.0")
      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)

      update_version_condition(deployment, ">= 0.1.0 and < 0.4.99")
      {:ok, :none} = Firmwares.get_eligible_firmware_update(device, version)
    end

    test "returns {:ok, %Firmware{}} properly with complex version conditions", %{
      firmware: firmware,
      deployment: deployment,
      matching_device: device
    } do
      version = Version.parse!("2.5.2")
      firmware_id = firmware.id

      deployment = update_version_condition(deployment, "~> 2.0")
      {:ok, %Firmware{id: ^firmware_id}} = Firmwares.get_eligible_firmware_update(device, version)

      deployment = update_version_condition(deployment, "~> 2.5")
      {:ok, %Firmware{id: ^firmware_id}} = Firmwares.get_eligible_firmware_update(device, version)

      deployment = update_version_condition(deployment, "~> 2.5.1")
      {:ok, %Firmware{id: ^firmware_id}} = Firmwares.get_eligible_firmware_update(device, version)

      update_version_condition(deployment, ">= 2.1.0 and < 2.37.12")
      {:ok, %Firmware{id: ^firmware_id}} = Firmwares.get_eligible_firmware_update(device, version)
    end
  end
end
