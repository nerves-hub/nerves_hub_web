defmodule NervesHubCore.DeploymentsTest do
  use NervesHubCore.DataCase
  use Phoenix.ChannelTest

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Deployments
  alias Ecto.Changeset

  setup do
    org = Fixtures.org_fixture()
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

  test "create_deployment with valid parameters", %{
    firmware: firmware
  } do
    params = %{
      firmware_id: firmware.id,
      name: "my deployment",
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

  describe "update_deployment" do
    test "updates correct devices", %{
      org: org,
      org_key: org_key,
      firmware: firmware,
      deployment: old_deployment,
      product: product
    } do
      device = Fixtures.device_fixture(org, firmware, old_deployment)
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

      device_topic = "device_socket:#{device.id}"
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
      deployment: old_deployment,
      product: product
    } do
      incorrect_params = [
        {%{version: "1.0.0"}, %{identifier: "foo"}},
        {%{}, %{identifier: "new identifier", tags: ["beta"]}},
        {%{}, %{identifier: "newnew identifier", architecture: "foo"}},
        {%{}, %{identifier: "newnewnew identifier", platform: "foo"}}
      ]

      for {f_params, d_params} <- incorrect_params do
        device = Fixtures.device_fixture(org, firmware, old_deployment, d_params)
        new_firmware = Fixtures.firmware_fixture(org_key, product, f_params)

        params = %{
          firmware_id: new_firmware.id,
          name: "my deployment",
          conditions: %{
            "version" => "< 1.0.0",
            "tags" => ["beta", "beta-edge"]
          },
          is_active: false
        }

        device_topic = "device_socket:#{device.id}"
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
