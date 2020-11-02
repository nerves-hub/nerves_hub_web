defmodule NervesHubWebCore.FirmwaresTest do
  use NervesHubWebCore.DataCase, async: true

  alias NervesHubWebCore.{
    Accounts,
    Accounts.OrgLimit,
    Firmwares,
    Firmwares.Firmware,
    Fixtures,
    Support.Fwup,
    Deployments,
    DeltaUpdaterMock,
    Products,
    UploadMock
  }

  alias Ecto.Changeset

  @uploader Application.get_env(:nerves_hub_web_core, :firmware_upload)
  @valid_fwup_version "1.6.0"

  setup context do
    Mox.verify_on_exit!(context)
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware)
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
       deployment: deployment,
       matching_device: device,
       product: product
     }}
  end

  describe "create_firmware/2" do
    test "remote creation failure triggers transaction rollback", %{
      org: org,
      org_key: org_key,
      product: product
    } do
      firmwares = Firmwares.get_firmwares_by_product(product.id)
      upload_file_2 = fn _, _ -> {:error, :nope} end
      filepath = Fixtures.firmware_file_fixture(org_key, product)

      assert {:error, _} =
               Firmwares.create_firmware(org, filepath, %{}, upload_file_2: upload_file_2)

      assert ^firmwares = Firmwares.get_firmwares_by_product(product.id)
    end

    test "enforces uuid uniqueness within a product",
         %{firmware: %{upload_metadata: %{local_path: filepath}}, org: org} do
      assert {:error, %Ecto.Changeset{errors: [uuid: {"has already been taken", [_ | _]}]}} =
               Firmwares.create_firmware(org, filepath)
    end

    test "enforces firmware limit within product", %{
      firmware: %{upload_metadata: %{local_path: filepath}},
      org: org,
      org_key: org_key,
      product: %{id: product_id} = product
    } do
      %{firmware_per_product: product_firmware_limit} = %OrgLimit{}
      current = product_id |> Firmwares.get_firmwares_by_product() |> length()

      if current < product_firmware_limit do
        for _ <- 1..(product_firmware_limit - current) do
          _firmware = Fixtures.firmware_fixture(org_key, product)
        end
      end

      assert {:error, %Changeset{errors: [product: {"firmware limit reached", []}]}} =
               Firmwares.create_firmware(org, filepath)
    end

    test "allow firmware per product limit to be raised", %{
      firmware: %{upload_metadata: %{local_path: filepath}},
      org: org,
      org_key: org_key,
      product: %{id: product_id} = product
    } do
      Accounts.create_org_limit(%{org_id: org.id, firmware_per_product: 10})

      %{firmware_per_product: product_firmware_limit} = %OrgLimit{}
      current = product_id |> Firmwares.get_firmwares_by_product() |> length()

      if current < product_firmware_limit do
        for _ <- 1..(product_firmware_limit - current) do
          _firmware = Fixtures.firmware_fixture(org_key, product)
        end
      end

      {:error, %Changeset{errors: errors}} = Firmwares.create_firmware(org, filepath)
      refute {"firmware limit reached", []} == Keyword.get(errors, :product)
    end
  end

  describe "delete_firmware/1" do
    test "remote deletion failure triggers transaction rollback", %{
      org: org,
      org_key: org_key,
      product: product
    } do
      firmware = Fixtures.firmware_fixture(org_key, product)
      @uploader.delete_file(firmware)

      # Make this path a directory will break delete_firmware/1
      # cause it to raise
      File.mkdir(firmware.upload_metadata.local_path)

      assert_raise File.Error, fn -> Firmwares.delete_firmware(firmware) end
      assert {:ok, _} = Firmwares.get_firmware(org, firmware.id)

      # Cleanup bogus directory
      File.rmdir!(firmware.upload_metadata.local_path)
    end

    test "delete firmware", %{org: org, org_key: org_key, product: product} do
      firmware = Fixtures.firmware_fixture(org_key, product)
      :ok = Firmwares.delete_firmware(firmware)
      refute File.exists?(firmware.upload_metadata[:local_path])
      assert {:error, :not_found} = Firmwares.get_firmware(org, firmware.id)
    end
  end

  test "cannot delete firmware when it is referenced by deployment", %{
    org: org,
    org_key: org_key,
    product: product
  } do
    firmware = Fixtures.firmware_fixture(org_key, product)
    assert File.exists?(firmware.upload_metadata[:local_path])

    Fixtures.deployment_fixture(org, firmware, %{name: "a deployment"})

    assert {:error, %Changeset{}} = Firmwares.delete_firmware(firmware)
  end

  test "firmware stores size", %{
    org: org,
    org_key: org_key,
    product: product
  } do
    firmware = Fixtures.firmware_fixture(org_key, product)
    assert File.exists?(firmware.upload_metadata[:local_path])

    expected_size =
      firmware.upload_metadata[:local_path]
      |> to_charlist()
      |> :filelib.file_size()

    {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

    assert firmware.size == expected_size
  end

  describe "get_firmwares_by_product/2" do
    test "returns firmwares", %{product: %{id: product_id} = product} do
      firmwares = Firmwares.get_firmwares_by_product(product.id)

      assert [%{product_id: ^product_id}] = firmwares
    end
  end

  describe "get_firmware/2" do
    test "returns firmwares", %{org: %{id: t_id} = org, firmware: %{id: f_id} = firmware} do
      {:ok, gotten_firmware} = Firmwares.get_firmware(org, firmware.id)

      assert %{id: ^f_id, product: %{org_id: ^t_id}} = gotten_firmware
    end
  end

  describe "verify_signature/2" do
    test "returns {:error, :no_public_keys} when no public keys are passed" do
      assert Firmwares.verify_signature("/fake/path", []) == {:error, :no_public_keys}
    end

    test "returns {:ok, key} when signature passes", %{
      org: org,
      org_key: org_key
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")

      assert Firmwares.verify_signature(signed_path, [org_key]) == {:ok, org_key}
      other_org_key = Fixtures.org_key_fixture(org)

      assert Firmwares.verify_signature(signed_path, [
               org_key,
               other_org_key
             ]) == {:ok, org_key}

      assert Firmwares.verify_signature(signed_path, [
               other_org_key,
               org_key
             ]) == {:ok, org_key}
    end

    test "returns {:error, :invalid_signature} when signature fails", %{
      org: org,
      org_key: org_key
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")
      other_org_key = Fixtures.org_key_fixture(org)

      assert Firmwares.verify_signature(signed_path, [other_org_key]) ==
               {:error, :invalid_signature}
    end

    test "returns {:error, :invalid_signature} on corrupt files", %{
      org_key: org_key
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")

      {:ok, corrupt_path} = Fwup.corrupt_firmware_file(signed_path)

      assert Firmwares.verify_signature(corrupt_path, [
               org_key
             ]) == {:error, :invalid_signature}
    end
  end

  describe "firmware ttl" do
    test "creating firmware sets ttl", %{org_key: org_key, product: product} do
      firmware = Fixtures.firmware_fixture(org_key, product)
      assert firmware.ttl != nil
      assert firmware.ttl_until != nil
    end

    test "associating firmware with deployment unsets ttl", %{
      org: org,
      org_key: org_key,
      product: product
    } do
      firmware = Fixtures.firmware_fixture(org_key, product)

      params = %{
        org_id: org.id,
        firmware_id: firmware.id,
        name: "firmware ttl",
        conditions: %{
          "version" => "",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      Deployments.create_deployment(params)

      {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

      assert firmware.ttl != nil
      assert firmware.ttl_until == nil
    end

    test "disassociating firmware from deployment unsets ttl", %{
      org: org,
      org_key: org_key,
      product: product
    } do
      firmware = Fixtures.firmware_fixture(org_key, product)

      params = %{
        org_id: org.id,
        firmware_id: firmware.id,
        name: "firmware ttl",
        conditions: %{
          "version" => "",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, deployment} = Deployments.create_deployment(params)

      {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

      assert firmware.ttl != nil
      assert firmware.ttl_until == nil

      Deployments.delete_deployment(deployment)

      {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

      assert firmware.ttl != nil
      assert firmware.ttl_until != nil
    end

    test "garbage collect old firmware", %{org_key: org_key, product: product} do
      firmware = Fixtures.firmware_fixture(org_key, product, %{ttl: 1})
      :timer.sleep(2_500)
      firmwares = Firmwares.get_firmware_by_expired_ttl()
      assert Enum.find(firmwares, &(&1.id == firmware.id)) != nil
    end

    test "passing an empty ttl sets defaults", %{org_key: org_key, product: product} do
      firmware = Fixtures.firmware_fixture(org_key, product, %{ttl: ""})
      assert firmware.ttl != ""
    end
  end

  describe "firmware transfers" do
    test "create", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "transfer-create"})
      assert {:ok, _transfer} = Fixtures.firmware_transfer_fixture(org.id, "12345")
    end

    test "cannot create records for orgs that do not exist" do
      assert {:error, _} = Fixtures.firmware_transfer_fixture(9_999_999_999, "12345")
    end
  end

  describe "get_firmware_delta/1" do
    test "a firmware delta is returned for the id", %{
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product)
      firmware_delta = Fixtures.firmware_delta_fixture(firmware, new_firmware)
      id = firmware_delta.id

      assert {:ok, %{id: ^id}} = Firmwares.get_firmware_delta(firmware_delta.id)
    end
  end

  describe "get_firmware_delta_by_source_and_target/2" do
    test "a firmware delta is returned matching source and target", %{
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product)
      firmware_delta = Fixtures.firmware_delta_fixture(firmware, new_firmware)
      id = firmware_delta.id

      assert {:ok, %{id: ^id}} =
               Firmwares.get_firmware_delta_by_source_and_target(firmware, new_firmware)
    end

    test ":not_found is returned when there is no match", %{
      firmware: firmware,
      org_key: org_key,
      product: product
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product)

      assert {:error, :not_found} =
               Firmwares.get_firmware_delta_by_source_and_target(firmware, new_firmware)
    end
  end

  describe "get_firmware_url/4" do
    test "returns target download_file when there is no source", %{
      firmware: target,
      product: product
    } do
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn ^target -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(nil, target, @valid_fwup_version, product)
    end

    test "returns target download_file when source does not support delta updating", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      target = Fixtures.firmware_fixture(org_key, product)
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn ^target -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, @valid_fwup_version, product)
    end

    test "returns target download_file when target does not support delta updating", %{
      firmware: target,
      org_key: org_key,
      product: product
    } do
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      source = Fixtures.firmware_fixture(org_key, product)
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn ^target -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, @valid_fwup_version, product)
    end

    test "returns target download_file when fwup version is too old", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      source = %Firmware{source | delta_updatable: true}
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      target = Fixtures.firmware_fixture(org_key, product)
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn ^target -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, "1.5.999", product)
    end

    test "returns target download_file when product does not support delta updating", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      {:ok, product} = Products.update_product(product, %{delta_updatable: false})
      source = %Firmware{source | delta_updatable: true}
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      target = Fixtures.firmware_fixture(org_key, product)
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn ^target -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, @valid_fwup_version, product)
    end

    test "returns firmware delta download_file when one exists", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      source = %Firmware{source | delta_updatable: true}
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      target = Fixtures.firmware_fixture(org_key, product)
      firmware_delta = Fixtures.firmware_delta_fixture(source, target)
      firmware_delta_id = firmware_delta.id
      url = "http://somefilestore.com/firmware.fw"
      Mox.expect(UploadMock, :download_file, fn %{id: ^firmware_delta_id} -> {:ok, url} end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, @valid_fwup_version, product)
    end

    test "returns download_file for a new firmware delta", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      source = %Firmware{source | delta_updatable: true}
      Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> true end)
      target = Fixtures.firmware_fixture(org_key, product)
      url = "http://somefilestore.com/firmware.fw"
      firmware_delta_path = "/path/to/firmware.fw"
      Mox.expect(UploadMock, :download_file, 3, fn _ -> {:ok, url} end)

      Mox.expect(DeltaUpdaterMock, :create_firmware_delta_file, fn ^url, ^url ->
        firmware_delta_path
      end)

      Mox.expect(UploadMock, :upload_file, fn ^firmware_delta_path, _ -> :ok end)

      Mox.expect(DeltaUpdaterMock, :cleanup_firmware_delta_files, fn ^firmware_delta_path ->
        :ok
      end)

      assert {:ok, url} = Firmwares.get_firmware_url(source, target, @valid_fwup_version, product)
    end
  end

  describe "create_firmware_delta/2" do
    test "creates a new firmware delta when one doesn't exist", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      target = Fixtures.firmware_fixture(org_key, product)
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"
      firmware_delta_path = "/path/to/firmware_delta.fw"

      UploadMock
      |> Mox.expect(:download_file, fn ^source -> {:ok, source_url} end)
      |> Mox.expect(:download_file, fn ^target -> {:ok, target_url} end)

      Mox.expect(DeltaUpdaterMock, :create_firmware_delta_file, fn ^source_url, ^target_url ->
        firmware_delta_path
      end)

      Mox.expect(UploadMock, :upload_file, fn ^firmware_delta_path, _ -> :ok end)

      Mox.expect(DeltaUpdaterMock, :cleanup_firmware_delta_files, fn ^firmware_delta_path ->
        :ok
      end)

      Firmwares.create_firmware_delta(source, target)

      assert {:ok, firmware_delta} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end

    test "new firmware delta is not created if there is an error", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      target = Fixtures.firmware_fixture(org_key, product)

      Mox.expect(DeltaUpdaterMock, :create_firmware_delta_file, fn _s, _t ->
        "path/to/firmware.fw"
      end)

      Mox.expect(UploadMock, :upload_file, fn _p, _m -> {:error, :failed} end)

      Firmwares.create_firmware_delta(source, target)

      assert {:error, :not_found} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end
  end
end
