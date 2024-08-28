defmodule NervesHub.Deployments.CalculatorTest do
  use NervesHub.DataCase

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Calculator
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "processes inflight checks" do
    test "matching device without a deployment" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware, %{conditions: %{"tags" => ["rpi"]}})
      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})
      deployment = %{deployment | firmware: firmware}

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})

      Deployments.create_inflight_checks(deployment)

      assert :ok = Calculator.process_next_device(deployment)

      device = Repo.reload(device)
      assert device.deployment_id == deployment.id
    end

    test "matching device already matched" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware, %{conditions: %{"tags" => ["rpi"]}})
      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})
      deployment = %{deployment | firmware: firmware}

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})
      device = Deployments.set_deployment(device)
      assert device.deployment_id == deployment.id

      Deployments.create_inflight_checks(deployment)

      assert :ok = Calculator.process_next_device(deployment)

      device = Repo.reload(device)
      assert device.deployment_id == deployment.id
    end

    test "device has another deployment already" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      original_deployment =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      {:ok, original_deployment} =
        Deployments.update_deployment(original_deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})
      device = Deployments.set_deployment(device)
      assert device.deployment_id == original_deployment.id

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi two",
          conditions: %{"tags" => ["rpi"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})
      deployment = %{deployment | firmware: firmware}

      Deployments.create_inflight_checks(deployment)

      assert :skipped = Calculator.process_next_device(deployment)

      device = Repo.reload(device)
      assert device.deployment_id == original_deployment.id
    end

    test "device is matched but no longer matches" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})
      device = Deployments.set_deployment(device)
      assert device.deployment_id == deployment.id

      deployment = %{deployment | conditions: %{"tags" => ["rpi0"]}}

      Deployments.create_inflight_checks(deployment)

      assert :ok = Calculator.process_next_device(deployment)

      device = Repo.reload(device)
      assert is_nil(device.deployment_id)
    end

    test "is_active is false unsets deployment from matching device" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware, %{conditions: %{"tags" => ["rpi"]}})
      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})
      deployment = %{deployment | firmware: firmware}

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})
      device = Deployments.set_deployment(device)
      assert device.deployment_id == deployment.id

      Deployments.create_inflight_checks(deployment)

      deployment = %{deployment | is_active: false}

      assert :ok = Calculator.process_next_device(deployment)

      device = Repo.reload(device)
      assert is_nil(device.deployment_id)
    end

    test "no more inflight checks left" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(org, firmware)

      assert :skipped = Calculator.process_next_device(deployment)
    end
  end
end
