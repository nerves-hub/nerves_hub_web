defmodule NervesHubWebCore.DeploymentsTest do
  use NervesHubWebCore.DataCase, async: false
  import Phoenix.ChannelTest

  alias NervesHubWebCore.{AuditLogs.AuditLog, Deployments, Fixtures, Firmwares}
  alias Ecto.Changeset

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)

    user2 = Fixtures.user_fixture(%{username: "user2", email: "user2@test.com"})
    org2 = Fixtures.org_fixture(user2, %{name: "org2"})
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2)
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
    test "updates correct devices", %{
      org: org,
      org2: org2,
      org_key: org_key,
      firmware: firmware,
      firmware2: firmware2,
      product: product
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "beta-edge"]})
      _device2 = Fixtures.device_fixture(org2, product, firmware2, %{tags: ["beta", "beta-edge"]})

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

      device_topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, device_topic)

      {:ok, deployment} =
        Deployments.create_deployment(params)
        |> elem(1)
        |> Deployments.update_deployment(%{is_active: true})

      {:ok, meta} = Firmwares.metadata_from_firmware(new_firmware)

      assert [^device] = Deployments.fetch_relevant_devices(deployment)
      assert_broadcast("update", %{firmware_url: _f_url, firmware_meta: ^meta}, 500)
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
        device = Fixtures.device_fixture(org, product, firmware, d_params)
        new_firmware = Fixtures.firmware_fixture(org_key, product, f_params)

        params = %{
          org_id: org.id,
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

        {:ok, meta} = Firmwares.metadata_from_firmware(new_firmware)

        refute_broadcast("update", %{firmware_url: _f_url, firmware_meta: ^meta})
      end
    end

    test "does not update devices if deployment in unhealthy state", %{
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta", "beta-edge"]})
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      params = %{
        org_id: org.id,
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
        |> Deployments.update_deployment(%{is_active: true, healthy: false})

      {:ok, meta} = Firmwares.metadata_from_firmware(new_firmware)

      refute_broadcast("update", %{firmware_url: _f_url, firmware_meta: ^meta})
    end

    test "does not update devices if device in unhealthy state", %{
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product
    } do
      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "beta-edge"],
          healthy: false
        })

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

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

      device_topic = "device:#{device.id}"
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, device_topic)

      {:ok, _deployment} =
        Deployments.create_deployment(params)
        |> elem(1)
        |> Deployments.update_deployment(%{is_active: true})

      {:ok, meta} = Firmwares.metadata_from_firmware(new_firmware)

      refute_broadcast("update", %{firmware_url: _f_url, firmware_meta: ^meta})
    end

    test "failure_threshold_met?", %{
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product
    } do
      # Create many devices in error state
      Enum.each(
        1..4,
        &Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta", "beta-edge", "#{&1}"],
          healthy: false
        })
      )

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1"})

      params = %{
        firmware_id: new_firmware.id,
        org_id: org.id,
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.1",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false,
        failure_threshold: 2
      }

      {:ok, deployment} = Deployments.create_deployment(params)

      assert Deployments.failure_threshold_met?(deployment)
    end
  end

  describe "failure_rate_met?" do
    setup context do
      # Create multi AuditLogs for deployment 1 to signify same device attempting to apply
      # the same update but failing
      Enum.each(1..5, fn i ->
        device = Fixtures.device_fixture(context.org, context.product, context.firmware)
        al = AuditLog.build(context.deployment, device, :update, %{send_update_message: true})
        time = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        Repo.insert(al)
        Repo.insert(%{al | inserted_at: Timex.shift(time, seconds: i)})
        Repo.insert(%{al | inserted_at: Timex.shift(time, seconds: i + 5)})
      end)

      context
    end

    test "when failure rate exceeded", %{deployment: deployment} do
      assert Deployments.failure_rate_met?(deployment)
    end

    test "skips failures that don't match deployment and firmware", %{
      deployment: deployment,
      firmware2: firmware2
    } do
      assert Deployments.failure_rate_met?(deployment)

      # Simulate updating a deployment with new firmware. So existing failures
      # tied to old firmware will not be counted in the rate check
      {:ok, deployment} = Deployments.update_deployment(deployment, %{firmware_id: firmware2.id})

      refute Deployments.failure_rate_met?(deployment)
    end
  end
end
