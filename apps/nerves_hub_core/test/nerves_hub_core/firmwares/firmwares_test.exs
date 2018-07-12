defmodule NervesHubCore.FirmwaresTest do
  use NervesHubCore.DataCase

  alias NervesHub.Fixtures
  alias NervesHubCore.{Firmwares, Repo}
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Accounts.TenantKey

  alias Ecto.Changeset

  @test_firmware_path "../../test/fixtures/firmware"
  @unsigned_firmware_path Path.join(@test_firmware_path, "unsigned.fw")
  @signed_key1_firmware_path Path.join(@test_firmware_path, "signed-key1.fw")
  @signed_other_key_firmware_path Path.join(@test_firmware_path, "signed-other-key.fw")
  @corrupt_firmware_path Path.join(@test_firmware_path, "signed-other-key.fw")
  @firmware_pub_key1 %TenantKey{
    id: "key1",
    key: File.read!(Path.join(@test_firmware_path, "fwup-key1.pub"))
  }
  @firmware_pub_key2 %TenantKey{
    id: "key2",
    key: File.read!(Path.join(@test_firmware_path, "fwup-key2.pub"))
  }

  setup do
    tenant = Fixtures.tenant_fixture()
    product = Fixtures.product_fixture(tenant)
    tenant_key = Fixtures.tenant_key_fixture(tenant)
    firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)
    deployment = Fixtures.deployment_fixture(tenant, firmware, product)
    device = Fixtures.device_fixture(tenant, firmware, deployment, product)

    {:ok,
     %{
       tenant: tenant,
       firmware: firmware,
       deployment: deployment,
       matching_device: device,
       product: product
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

  describe "NervesHub.Firmwares.get_firmwares_by_product/2" do
    test "returns firmwares", %{product: %{id: product_id} = product} do
      firmwares = Firmwares.get_firmwares_by_product(product.id)

      assert [%{product_id: ^product_id}] = firmwares
    end
  end

  describe "NervesHub.Firmwares.get_firmware/2" do
    test "returns firmwares", %{tenant: %{id: t_id} = tenant, firmware: %{id: f_id} = firmware} do
      {:ok, gotten_firmware} = Firmwares.get_firmware(tenant, firmware.id)

      assert %{id: ^f_id, tenant_id: ^t_id} = gotten_firmware
    end
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
         %{product: product, matching_device: device} do
      device = %{device | product_id: product.id + 1}
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

  describe "NervesHubCore.Firmwares.verify_signature/2" do
    test "returns {:error, :no_public_keys} when no public keys are passed" do
      assert Firmwares.verify_signature(@unsigned_firmware_path, []) == {:error, :no_public_keys}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, []) ==
               {:error, :no_public_keys}

      assert Firmwares.verify_signature(@signed_other_key_firmware_path, []) ==
               {:error, :no_public_keys}
    end

    test "returns {:ok, key} when signature passes" do
      assert Firmwares.verify_signature(@signed_key1_firmware_path, [@firmware_pub_key1]) ==
               {:ok, @firmware_pub_key1}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:ok, @firmware_pub_key1}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, [
               @firmware_pub_key2,
               @firmware_pub_key1
             ]) == {:ok, @firmware_pub_key1}
    end

    test "returns {:error, :invalid_signature} when signature fails" do
      assert Firmwares.verify_signature(@signed_key1_firmware_path, [@firmware_pub_key2]) ==
               {:error, :invalid_signature}

      assert Firmwares.verify_signature(@signed_other_key_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:error, :invalid_signature}

      assert Firmwares.verify_signature(@unsigned_firmware_path, [@firmware_pub_key1]) ==
               {:error, :invalid_signature}
    end

    test "returns {:error, :invalid_signature} on corrupt files" do
      assert Firmwares.verify_signature(@corrupt_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:error, :invalid_signature}
    end
  end
end
