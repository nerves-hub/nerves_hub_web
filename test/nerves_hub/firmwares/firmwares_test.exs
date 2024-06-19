defmodule NervesHub.FirmwaresTest do
  use NervesHub.DataCase, async: true
  use Oban.Testing, repo: NervesHub.Repo

  alias NervesHub.{
    Firmwares,
    Firmwares.Firmware,
    Repo,
    Fixtures,
    Support.Fwup,
    DeltaUpdaterMock,
    UploadMock
  }

  alias Ecto.Changeset

  setup context do
    Mox.verify_on_exit!(context)
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
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

      assert {:error, _} = Firmwares.create_firmware(org, filepath, upload_file_2: upload_file_2)

      assert ^firmwares = Firmwares.get_firmwares_by_product(product.id)
    end

    test "enforces uuid uniqueness within a product",
         %{firmware: %{upload_metadata: %{local_path: filepath}}, org: org} do
      assert {:error, %Ecto.Changeset{errors: [uuid: {"has already been taken", [_ | _]}]}} =
               Firmwares.create_firmware(org, filepath)
    end
  end

  describe "delete_firmware/1" do
    test "delete firmware", %{org: org, org_key: org_key, product: product} do
      firmware = Fixtures.firmware_fixture(org_key, product)
      {:ok, _} = Firmwares.delete_firmware(firmware)

      assert_enqueued(
        worker: NervesHub.Workers.DeleteFirmware,
        args: %{
          "local_path" => firmware.upload_metadata[:local_path],
          "public_path" => firmware.upload_metadata[:public_path]
        }
      )

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

  describe "get_firmwares_by_product/1" do
    test "returns firmwares", %{
      product: product,
      org_key: org_key,
      firmware: %{id: first2_same_ver, version: version}
    } do
      product_id = product.id

      %{id: oldest_ver} = Fixtures.firmware_fixture(org_key, product, %{version: "0.1.0"})

      %{id: middle2_same_ver, inserted_at: dt} =
        Fixtures.firmware_fixture(org_key, product, %{version: "0.5.1"})

      # We need to force the inserted_at times here to be different to test
      # correct ordering with same version, different creation time
      %{id: middle1_same_ver} =
        Fixtures.firmware_fixture(org_key, product, %{version: "0.5.1"})
        |> Firmware.update_changeset(%{})
        |> Ecto.Changeset.put_change(:inserted_at, NaiveDateTime.add(dt, 5))
        |> Repo.update!()

      %{id: first1_same_ver} =
        Fixtures.firmware_fixture(org_key, product, %{version: version})
        |> Firmware.update_changeset(%{})
        |> Ecto.Changeset.put_change(:inserted_at, NaiveDateTime.add(dt, 6))
        |> Repo.update!()

      firmwares = Firmwares.get_firmwares_by_product(product.id)

      assert [
               %{id: ^first1_same_ver, product_id: ^product_id},
               %{id: ^first2_same_ver, product_id: ^product_id},
               %{id: ^middle1_same_ver, product_id: ^product_id},
               %{id: ^middle2_same_ver, product_id: ^product_id},
               %{id: ^oldest_ver, product_id: ^product_id}
             ] = firmwares
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
      user: user,
      org: org,
      org_key: org_key
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")

      assert Firmwares.verify_signature(signed_path, [org_key]) == {:ok, org_key}
      other_org_key = Fixtures.org_key_fixture(org, user)

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
      user: user,
      org: org,
      org_key: org_key
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")
      other_org_key = Fixtures.org_key_fixture(org, user)

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

      assert {:ok, _firmware_delta} =
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

      Mox.expect(DeltaUpdaterMock, :cleanup_firmware_delta_files, fn _p -> :ok end)

      Firmwares.create_firmware_delta(source, target)

      assert {:error, :not_found} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end
  end
end
