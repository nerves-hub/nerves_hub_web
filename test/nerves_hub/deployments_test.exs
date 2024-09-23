defmodule NervesHub.DeploymentsTest do
  use NervesHub.DataCase, async: false
  import Phoenix.ChannelTest

  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias Ecto.Changeset

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)

    user2 = Fixtures.user_fixture(%{email: "user2@test.com"})
    org2 = Fixtures.org_fixture(user2, %{name: "org2"})
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2, user2)
    firmware2 = Fixtures.firmware_fixture(org_key2, product2)
    deployment2 = Fixtures.deployment_fixture(org2, firmware2)

    {:ok,
     %{
       org: org,
       org_key: org_key,
       firmware: firmware,
       deployment: deployment,
       product: product,
       org2: org2,
       org_key2: org_key2,
       firmware2: firmware2,
       deployment2: deployment2,
       product2: product2
     }}
  end

  describe "create deployment" do
    test "create_deployment with valid parameters", %{
      org: org,
      firmware: firmware
    } do
      params = %{
        org_id: org.id,
        firmware_id: firmware.id,
        name: "a different name",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, %Deployments.Deployment{} = deployment} = Deployments.create_deployment(params)

      for key <- Map.keys(params) do
        assert Map.get(deployment, key) == Map.get(params, key)
      end
    end

    test "deployments have unique names wrt product", %{
      org: org,
      firmware: firmware,
      deployment: existing_deployment
    } do
      params = %{
        name: existing_deployment.name,
        org_id: org.id,
        firmware_id: firmware.id,
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", _}]}} =
               Deployments.create_deployment(params)
    end

    test "create_deployment with invalid parameters" do
      params = %{
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: true
      }

      assert {:error, %Changeset{}} = Deployments.create_deployment(params)
    end
  end

  describe "update_deployment" do
    test "updating firmware sends an update message", %{
      org: org,
      org_key: org_key,
      firmware: firmware,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      Fixtures.firmware_delta_fixture(firmware, new_firmware)

      params = %{
        firmware_id: new_firmware.id,
        org_id: org.id,
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, deployment} = Deployments.create_deployment(params)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

      {:ok, _deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      assert_broadcast("deployments/update", %{}, 500)
    end

    test "changing tags resets device's deployments and causes a recalculation", state do
      %{firmware: firmware, org: org, product: product} = state

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{name: "name", conditions: %{tags: ["alpha"]}})

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device_one = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})
      device_two = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})

      device_one = Deployments.set_deployment(device_one)
      assert device_one.deployment_id == deployment.id
      device_two = Deployments.set_deployment(device_two)
      assert device_two.deployment_id == deployment.id

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{conditions: %{"tags" => ["beta"]}})

      assert deployment.conditions == %{"tags" => ["beta"]}

      device_one = Repo.reload(device_one)
      refute device_one.deployment_id
      device_two = Repo.reload(device_two)
      refute device_two.deployment_id

      assert_broadcast("deployments/changed", %{}, 500)
    end

    test "changing tags with empty version causes recalculation", state do
      %{firmware: firmware, org: org, product: product} = state

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{name: "name", conditions: %{tags: ["alpha"]}})

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      device_one = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})
      device_two = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})

      device_one = Deployments.set_deployment(device_one)
      assert device_one.deployment_id == deployment.id
      device_two = Deployments.set_deployment(device_two)
      refute device_two.deployment_id == deployment.id

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{
          conditions: %{"tags" => ["beta"], "version" => ""}
        })

      assert deployment.conditions == %{"tags" => ["beta"], "version" => ""}

      device_one = Repo.reload(device_one)
      refute device_one.deployment_id
      device_two = Repo.reload(device_two)
      assert device_two.deployment_id

      assert_broadcast("deployments/changed", %{}, 500)
    end

    test "changing is_active causes a recaluation", state do
      %{firmware: firmware, org: org, product: product} = state

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{name: "name", conditions: %{tags: ["alpha"]}})

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:none")

      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      Phoenix.PubSub.unsubscribe(NervesHub.PubSub, "deployment:none")

      assert_broadcast("deployments/changed", %{}, 500)

      device_one = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})
      device_two = Fixtures.device_fixture(org, product, firmware, %{tags: ["alpha"]})

      device_one = Deployments.set_deployment(device_one)
      assert device_one.deployment_id == deployment.id
      device_two = Deployments.set_deployment(device_two)
      assert device_two.deployment_id == deployment.id

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{conditions: %{"tags" => ["beta"]}})

      assert deployment.conditions == %{"tags" => ["beta"]}

      assert_broadcast("deployments/changed", %{}, 500)

      device_one = Repo.reload(device_one)
      refute device_one.deployment_id
      device_two = Repo.reload(device_two)
      refute device_two.deployment_id
    end
  end

  describe "device's matching deployments" do
    test "finds all matching deployments", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: beta_deployment_id} =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "beta",
          conditions: %{"tags" => ["beta"]}
        })

      %{id: rpi_deployment_id} =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi0"]}
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [
               %{id: ^beta_deployment_id},
               %{id: ^rpi_deployment_id}
             ] = Deployments.alternate_deployments(device)
    end

    test "finds matching deployments including the platform", state do
      %{org: org, org_key: org_key, product: product} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "rpi0"})

      %{id: rpi_deployment_id} =
        Fixtures.deployment_fixture(org, rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_fixture(org, rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"]}
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_id}] = Deployments.alternate_deployments(device)
    end

    test "finds matching deployments including the architecture", state do
      %{org: org, org_key: org_key, product: product} = state

      rpi_firmware = Fixtures.firmware_fixture(org_key, product, %{architecture: "rpi"})
      rpi0_firmware = Fixtures.firmware_fixture(org_key, product, %{architecture: "rpi0"})

      %{id: rpi_deployment_id} =
        Fixtures.deployment_fixture(org, rpi_firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"]}
        })

      Fixtures.deployment_fixture(org, rpi0_firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"]}
      })

      device = Fixtures.device_fixture(org, product, rpi_firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^rpi_deployment_id}] = Deployments.alternate_deployments(device)
    end

    test "finds matching deployments including the version", state do
      %{org: org, product: product, firmware: firmware} = state

      %{id: low_deployment_id} =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"}
      })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_id}] = Deployments.alternate_deployments(device)
    end

    test "finds matching deployments including pre versions", state do
      %{org: org, org_key: org_key, product: product, firmware: firmware} = state

      %{id: low_deployment_id} =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "rpi",
          conditions: %{"tags" => ["rpi"], "version" => "~> 1.0"}
        })

      Fixtures.deployment_fixture(org, firmware, %{
        name: "rpi0",
        conditions: %{"tags" => ["rpi"], "version" => "~> 2.0"}
      })

      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.2.0-pre"})

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "rpi"]})

      assert [%{id: ^low_deployment_id}] = Deployments.alternate_deployments(device)
    end

    test "finds the newest firmware version including pre-releases", state do
      %{
        org: org,
        org_key: org_key,
        product: product,
        firmware: %{version: "1.0.0"} = v100_firmware
      } = state

      v090_fw = Fixtures.firmware_fixture(org_key, product, %{version: "0.9.0"})
      v100rc1_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.1"})
      v100rc2_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0-rc.2"})
      v101_fw = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      %{id: v100_deployment_id} =
        Fixtures.deployment_fixture(org, v100_firmware, %{
          name: v100_firmware.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc1_deployment_id} =
        Fixtures.deployment_fixture(org, v100rc1_fw, %{
          name: v100rc1_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v100rc2_deployment_id} =
        Fixtures.deployment_fixture(org, v100rc2_fw, %{
          name: v100rc2_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      %{id: v101_deployment_id} =
        Fixtures.deployment_fixture(org, v101_fw, %{
          name: v101_fw.version,
          conditions: %{"version" => "", "tags" => ["next"]}
        })

      device = Fixtures.device_fixture(org, product, v090_fw, %{tags: ["next"]})

      assert [
               %{id: ^v101_deployment_id},
               %{id: ^v100_deployment_id},
               %{id: ^v100rc2_deployment_id},
               %{id: ^v100rc1_deployment_id}
             ] = Deployments.alternate_deployments(device)
    end
  end

  describe "calculate deployment" do
    test "matching device without a deployment", state do
      %{org: org, org_key: org_key, product: product, deployment: deployment} = state

      firmware = Fixtures.firmware_fixture(org_key, product)

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{
          is_active: true,
          firmware: firmware,
          conditions: %{"tags" => ["rpi"]}
        })

      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["rpi"]})
      {:ok, _} = Devices.device_connected(device)

      Deployments.schedule_deployment_calculations(deployment)

      # Due to the way jobs are created via sql, we can't use the Oban helpers
      count =
        Oban.Job
        |> where([oj], oj.worker == "NervesHub.Workers.DeviceCalculateDeployment")
        |> Repo.aggregate(:count)

      assert ^count = 1
    end
  end

  test "alternate_deployments/2 ignores device without firmware metadata" do
    assert [] == Deployments.alternate_deployments(%Device{firmware_metadata: nil})
    assert [] == Deployments.alternate_deployments(%Device{firmware_metadata: nil}, [true])
    assert [] == Deployments.alternate_deployments(%Device{firmware_metadata: nil}, [false])
  end
end
