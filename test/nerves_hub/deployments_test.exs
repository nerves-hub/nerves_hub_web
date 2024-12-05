defmodule NervesHub.DeploymentsTest do
  use NervesHub.DataCase, async: false
  import Phoenix.ChannelTest

  alias NervesHub.Deployments
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
  end
end
