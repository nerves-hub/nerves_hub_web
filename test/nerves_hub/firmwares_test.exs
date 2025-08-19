defmodule NervesHub.FirmwaresTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool.Fwup, as: UpdateToolDefault
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.Upload.File, as: UploadFile
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Support.Fwup
  alias NervesHub.Workers.FirmwareDeltaBuilder

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
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

    Fixtures.deployment_group_fixture(org, firmware, %{name: "a deployment"})

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
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")
      other_org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      assert Firmwares.verify_signature(signed_path, [other_org_key]) ==
               {:error, :invalid_signature}
    end

    test "returns {:error, :invalid_signature} on corrupt files", %{
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed")

      {:ok, corrupt_path} = Fwup.corrupt_firmware_file(signed_path, tmp_dir)

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
    @tag :tmp_dir
    test "creates a new firmware delta when one doesn't exist", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product)
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"
      firmware_delta_path = Path.join(tmp_dir, "firmware_delta.fw")
      File.cp!("test/fixtures/fwup/mixed.conf", firmware_delta_path)

      expect(UploadFile, :download_file, fn ^source -> {:ok, source_url} end)
      expect(UploadFile, :download_file, fn ^target -> {:ok, target_url} end)

      expect(UpdateToolDefault, :create_firmware_delta_file, fn {_, ^source_url}, {_, ^target_url} ->
        {:ok,
         %{
           filepath: firmware_delta_path,
           size: 5,
           source_size: 10,
           target_size: 15,
           tool: "fwup",
           tool_metadata: %{}
         }}
      end)

      expect(UploadFile, :upload_file, fn ^firmware_delta_path, _ -> :ok end)

      expect(UpdateToolDefault, :cleanup_firmware_delta_files, fn ^firmware_delta_path ->
        :ok
      end)

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source, target)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, _firmware_delta} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end

    test "new firmware delta is not created if there is an error", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      target = Fixtures.firmware_fixture(org_key, product)

      expect(UpdateToolDefault, :create_firmware_delta_file, fn _s, _t ->
        {:ok,
         %{
           filepath: "path/to/firmware.fw",
           size: 5,
           source_size: 10,
           target_size: 15,
           tool: "fwup",
           tool_metadata: %{}
         }}
      end)

      expect(UploadFile, :upload_file, fn _p, _m -> {:error, :failed} end)

      expect(UpdateToolDefault, :cleanup_firmware_delta_files, fn _p -> :ok end)

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source.id, target.id)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, %FirmwareDelta{status: :failed}} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end

    test "update tool errors are handled", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      target = Fixtures.firmware_fixture(org_key, product)
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"

      expect(UploadFile, :download_file, fn ^source -> {:ok, source_url} end)
      expect(UploadFile, :download_file, fn ^target -> {:ok, target_url} end)

      # Force error
      expect(UpdateToolDefault, :create_firmware_delta_file, fn {_, ^source_url}, {_, ^target_url} ->
        {:error, :delta_not_created}
      end)

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source, target)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, _} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end

    @tag :tmp_dir
    test "firmware deltas progress through status steps", %{
      firmware: %{id: source_id} = source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      %{id: target_id} = target = Fixtures.firmware_fixture(org_key, product)
      firmware_delta_path = Path.join(tmp_dir, "firmware_delta.fw")
      File.cp!("test/fixtures/fwup/mixed.conf", firmware_delta_path)

      assert {:ok, %FirmwareDelta{status: :processing, tool: "pending"}} =
               Firmwares.attempt_firmware_delta(source.id, target.id)

      assert_enqueued(
        args: %{source_id: source_id, target_id: target_id},
        worker: FirmwareDeltaBuilder,
        queue: :firmware_delta_builder
      )

      expect(UpdateToolDefault, :create_firmware_delta_file, fn _, _ ->
        {:ok,
         %{
           filepath: firmware_delta_path,
           size: 5,
           source_size: 10,
           target_size: 15,
           tool: "fwup",
           tool_metadata: %{}
         }}
      end)

      assert :ok =
               perform_job(FirmwareDeltaBuilder, %{source_id: source_id, target_id: target_id})

      assert {:ok, %FirmwareDelta{status: :completed, tool: "fwup"}} =
               Firmwares.get_firmware_delta_by_source_and_target(source, target)
    end
  end

  describe "time_out_firmware_delta_generations/1" do
    test "time out old delta generations but not new ones", %{
      firmware: source,
      org_key: org_key,
      product: product
    } do
      t1 = Fixtures.firmware_fixture(org_key, product)
      t2 = Fixtures.firmware_fixture(org_key, product)
      t3 = Fixtures.firmware_fixture(org_key, product)
      t4 = Fixtures.firmware_fixture(org_key, product)
      {:ok, %{id: d1}} = Firmwares.start_firmware_delta(source, t1)
      {:ok, %{id: d2}} = Firmwares.start_firmware_delta(source, t2)
      :timer.sleep(2000)
      {:ok, %{id: d3}} = Firmwares.start_firmware_delta(source, t3)
      {:ok, %{id: d4}} = Firmwares.start_firmware_delta(source, t4)
      Firmwares.time_out_firmware_delta_generations(1000, :millisecond)

      assert [
               %{id: ^d1, status: :timed_out},
               %{id: ^d2, status: :timed_out},
               %{id: ^d3, status: :processing},
               %{id: ^d4, status: :processing}
             ] =
               get_deltas_by_source_firmware(source)
               |> Enum.sort_by(& &1.id)
    end
  end

  describe "filter/2" do
    test "counts the number of devices that have the firmware installed", %{
      org: org,
      firmware: firmware,
      product: product
    } do
      _device_2 = Fixtures.device_fixture(org, product, firmware)
      _device_3 = Fixtures.device_fixture(org, product, firmware)
      {[firmware], _} = Firmwares.filter(product)
      assert firmware.install_count == 3
    end
  end

  defp get_deltas_by_source_firmware(firmware) do
    FirmwareDelta
    |> where([fd], fd.source_id == ^firmware.id)
    |> Repo.all()
  end
end
