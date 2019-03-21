defmodule NervesHubWebCore.DeploymentsTest do
  use NervesHubWebCore.DataCase, async: false
  use Phoenix.ChannelTest

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Deployments
  alias Ecto.Changeset

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(firmware)

    {:ok,
     %{
       org: org,
       org_key: org_key,
       firmware: firmware,
       deployment: deployment,
       product: product
     }}
  end

  describe "create deployment" do
    test "create_deployment with valid parameters", %{
      firmware: firmware
    } do
      params = %{
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
      firmware: firmware,
      deployment: existing_deployment
    } do
      params = %{
        name: existing_deployment.name,
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
    test "updates correct devices", %{
      org: org,
      org_key: org_key,
      firmware: firmware,
      product: product
    } do
      device = Fixtures.device_fixture(org, firmware, %{tags: ["beta", "beta-edge"]})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      params = %{
        firmware_id: new_firmware.id,
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      device_topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, device_topic)

      {:ok, _deployment} =
        Deployments.create_deployment(params)
        |> elem(1)
        |> Deployments.update_deployment(%{is_active: true})

      assert_broadcast("update", %{firmware_url: _f_url}, 500)
    end

    test "does not update incorrect devices", %{
      org: org,
      org_key: org_key,
      firmware: firmware,
      product: product
    } do
      incorrect_params = [
        {%{version: "1.0.0"}, %{identifier: "foo"}},
        {%{}, %{identifier: "new identifier", tags: ["beta"]}},
        {%{}, %{identifier: "newnew identifier", architecture: "foo"}},
        {%{}, %{identifier: "newnewnew identifier", platform: "foo"}}
      ]

      for {f_params, d_params} <- incorrect_params do
        device = Fixtures.device_fixture(org, firmware, d_params)
        new_firmware = Fixtures.firmware_fixture(org_key, product, f_params)

        params = %{
          firmware_id: new_firmware.id,
          name: "my deployment #{d_params.identifier}",
          conditions: %{
            "version" => "< 1.0.0",
            "tags" => ["beta", "beta-edge"]
          },
          is_active: false
        }

        device_topic = "device:#{device.id}"
        Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, device_topic)

        {:ok, _deployment} =
          Deployments.create_deployment(params)
          |> elem(1)
          |> Deployments.update_deployment(%{is_active: true})

        refute_broadcast("update", %{firmware_url: _f_url})
      end
    end
  end
end
