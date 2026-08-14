defmodule NervesHub.FirmwaresTest do
  use NervesHub.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.UpdateTool.Fwup, as: UpdateToolDefault
  alias NervesHub.Firmwares.Upload.File, as: UploadFile
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Support.Fwup
  alias NervesHub.Workers.DeleteFirmware
  alias NervesHub.Workers.FirmwareDeltaBuilder

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
       matching_device: device,
       product: product,
       tmp_dir: tmp_dir
     }}
  end

  describe "create_firmware/2" do
    test "remote creation failure triggers transaction rollback", %{
      org: org,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      firmwares = Firmwares.get_firmwares_by_product(product.id)
      upload_file_2 = fn _, _ -> {:error, :nope} end
      filepath = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir})

      assert {:error, _} = Firmwares.create_firmware(org, filepath, upload_file_2: upload_file_2)

      assert ^firmwares = Firmwares.get_firmwares_by_product(product.id)
    end

    test "enforces uuid uniqueness within a product",
         %{firmware: %{upload_metadata: %{local_path: filepath}}, org: org} do
      assert {:error, %Ecto.Changeset{errors: [uuid: {"has already been taken", [_ | _]}]}} =
               Firmwares.create_firmware(org, filepath)
    end

    test "rejects a duplicate version when the product requires unique versions",
         %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{require_unique_firmware_version: true})

      path_a = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9"})
      assert {:ok, _} = Firmwares.create_firmware(org, path_a)

      path_b = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9"})
      assert {:error, changeset} = Firmwares.create_firmware(org, path_b)
      assert "has already been taken for this product" in errors_on(changeset).version
    end

    test "allows the same version for a different platform when unique versions are required",
         %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{require_unique_firmware_version: true})

      path_a =
        Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9", platform: "rpi0"})

      assert {:ok, _} = Firmwares.create_firmware(org, path_a)

      path_b =
        Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9", platform: "rpi4"})

      assert {:ok, _} = Firmwares.create_firmware(org, path_b)
    end

    test "allows a duplicate version when the product does not require unique versions",
         %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{require_unique_firmware_version: false})

      path_a = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9"})
      assert {:ok, _} = Firmwares.create_firmware(org, path_a)

      path_b = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir, version: "9.9.9"})
      assert {:ok, _} = Firmwares.create_firmware(org, path_b)
    end
  end

  describe "delete_firmware/1" do
    test "delete firmware", %{org: org, org_key: org_key, product: product, tmp_dir: tmp_dir} do
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      {:ok, _} = Firmwares.delete_firmware(firmware)

      assert_enqueued(
        worker: DeleteFirmware,
        args: %{
          "local_path" => firmware.upload_metadata[:local_path],
          "public_path" => firmware.upload_metadata[:public_path]
        }
      )

      assert {:error, :not_found} = Firmwares.get_firmware(org, firmware.id)
    end

    test "cannot delete firmware when it is referenced by deployment", %{
      user: user,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      assert File.exists?(firmware.upload_metadata[:local_path])

      Fixtures.deployment_group_fixture(firmware, %{name: "a deployment", user: user})

      assert {:error, %Changeset{}} = Firmwares.delete_firmware(firmware)
    end
  end

  test "deletes delta firmware and enqueues job", %{org_key: org_key, product: product, tmp_dir: tmp_dir} do
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    delta = Fixtures.firmware_delta_fixture(firmware2, firmware)
    {:ok, _} = Firmwares.delete_firmware_delta(delta)

    assert {:error, :not_found} = Firmwares.get_firmware_delta(delta.id)

    assert_enqueued(
      worker: DeleteFirmware,
      args: %{
        "local_path" => delta.upload_metadata[:local_path],
        "public_path" => delta.upload_metadata[:public_path]
      }
    )
  end

  test "firmware stores size", %{
    org: org,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir
  } do
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    assert File.exists?(firmware.upload_metadata[:local_path])

    expected_size =
      firmware.upload_metadata[:local_path]
      |> to_charlist()
      |> :filelib.file_size()

    {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

    assert firmware.size == expected_size
  end

  test "firmware stores its sha256 checksum, base16 encoded", %{
    org: org,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir
  } do
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    assert File.exists?(firmware.upload_metadata[:local_path])

    expected_checksum = Firmwares.firmware_checksum(firmware.upload_metadata[:local_path])

    {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

    assert firmware.checksum == expected_checksum
  end

  test "firmware stores checksums of 1MB parts of its full file, base16 encoded", %{
    org: org,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir
  } do
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    assert File.exists?(firmware.upload_metadata[:local_path])

    expected_checksums = Firmwares.partials_checksums(firmware.upload_metadata[:local_path])

    {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

    assert firmware.partials_checksums == expected_checksums
    assert length(firmware.partials_checksums) == 1
  end

  test "firmware stores checksums of 1MB parts of its full file, base16 encoded, using a larger file", %{
    org: org,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir
  } do
    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "1.0.0",
        resource_contents_path: "test/fixtures/fwup/dummy_4mb.txt",
        dir: tmp_dir
      })

    assert File.exists?(firmware.upload_metadata[:local_path])

    expected_checksums = Firmwares.partials_checksums(firmware.upload_metadata[:local_path])

    {:ok, firmware} = Firmwares.get_firmware(org, firmware.id)

    assert firmware.partials_checksums == expected_checksums
    assert length(firmware.partials_checksums) == 5
  end

  describe "get_firmwares_by_product/1" do
    test "returns firmwares", %{
      product: product,
      org_key: org_key,
      firmware: %{id: first2_same_ver, version: version},
      tmp_dir: tmp_dir
    } do
      product_id = product.id

      %{id: oldest_ver} = Fixtures.firmware_fixture(org_key, product, %{version: "0.1.0", dir: tmp_dir})

      %{id: middle2_same_ver, inserted_at: dt} =
        Fixtures.firmware_fixture(org_key, product, %{version: "0.5.1", dir: tmp_dir})

      # We need to force the inserted_at times here to be different to test
      # correct ordering with same version, different creation time
      %{id: middle1_same_ver} =
        Fixtures.firmware_fixture(org_key, product, %{version: "0.5.1", dir: tmp_dir})
        |> Firmware.update_changeset(%{})
        |> Ecto.Changeset.put_change(:inserted_at, NaiveDateTime.add(dt, 5))
        |> Repo.update!()

      %{id: first1_same_ver} =
        Fixtures.firmware_fixture(org_key, product, %{version: version, dir: tmp_dir})
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

  describe "SemVer version ordering" do
    setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
      product =
        Fixtures.product_fixture(user, org, %{name: "semver-order-#{System.unique_integer([:positive])}"})

      insert = fn version ->
        Fixtures.firmware_fixture(org_key, product, %{version: version, dir: tmp_dir})
      end

      {:ok, %{product: product, insert: insert}}
    end

    test "get_firmwares_by_product/1 orders by precedence, not lexically", %{
      product: product,
      insert: insert
    } do
      # Lexical/naive ordering would put 1.9.0 above 1.10.0 and a release below
      # its pre-release; SemVer precedence must not.
      for v <- ["1.2.0", "1.9.0", "1.10.0", "1.10.0-rc1"], do: insert.(v)

      versions =
        product.id
        |> Firmwares.get_firmwares_by_product()
        |> Enum.map(& &1.version)

      assert versions == ["1.10.0", "1.10.0-rc1", "1.9.0", "1.2.0"]
    end

    test "get_firmware_versions_by_product/1 returns distinct versions, newest first", %{
      product: product,
      insert: insert
    } do
      for v <- ["1.9.0", "1.10.0", "1.10.0-rc1"], do: insert.(v)

      assert Firmwares.get_firmware_versions_by_product(product.id) ==
               ["1.10.0", "1.10.0-rc1", "1.9.0"]
    end

    test "get_firmwares_by_product_and_platform/2 orders by precedence", %{
      product: product,
      insert: insert
    } do
      platform = insert.("1.9.0").platform
      insert.("1.10.0")

      versions =
        product
        |> Firmwares.get_firmwares_by_product_and_platform(platform)
        |> Enum.map(& &1.version)

      assert versions == ["1.10.0", "1.9.0"]
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
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{dir: tmp_dir})

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
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{dir: tmp_dir})
      other_org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      assert Firmwares.verify_signature(signed_path, [other_org_key]) ==
               {:error, :invalid_signature}
    end

    test "returns {:error, :invalid_signature} on corrupt files", %{
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      {:ok, signed_path} = Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{dir: tmp_dir})

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
      product: product,
      tmp_dir: tmp_dir
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_delta = Fixtures.firmware_delta_fixture(firmware, new_firmware)
      id = firmware_delta.id

      assert {:ok, %{id: ^id}} = Firmwares.get_firmware_delta(firmware_delta.id)
    end
  end

  describe "get_firmware_delta_by_source_and_target/2" do
    test "a firmware delta is returned matching source and target", %{
      firmware: firmware,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_delta = Fixtures.firmware_delta_fixture(firmware, new_firmware)
      id = firmware_delta.id

      assert {:ok, %{id: ^id}} =
               Firmwares.get_firmware_delta_by_source_and_target(firmware.id, new_firmware.id)
    end

    test ":not_found is returned when there is no match", %{
      firmware: firmware,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      assert {:error, :not_found} =
               Firmwares.get_firmware_delta_by_source_and_target(firmware.id, new_firmware.id)
    end
  end

  describe "generate_firmware_delta/3 for a format that cannot be patched" do
    @tag :tmp_dir
    test "refuses, without downloading either image", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      # Every format shipped today can be patched, so the format that cannot is
      # a stub. It is still worth covering: a format arrives without an applier
      # and gains one later, and until it does, a deployment group with deltas
      # enabled must not have patches built for it. Downloading is what makes
      # that expensive — two full images fetched to produce a file nothing can
      # use.
      stub(UpdateToolDefault, :supports_deltas?, fn -> false end)

      reject(&UploadFile.download_file/1)
      reject(&UpdateToolDefault.create_firmware_delta_file/3)

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source.id, target.id)

      assert {:error, :no_delta_support_in_firmware} =
               Firmwares.generate_firmware_delta(firmware_delta, source, target)
    end
  end

  describe "create_firmware_delta/2" do
    @tag :tmp_dir
    test "creates a new firmware delta when one doesn't exist, and saves the checksum and partials checksums", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"
      firmware_delta_path = Path.join(tmp_dir, "firmware_delta.fw")
      File.cp!("test/fixtures/fwup/mixed.conf", firmware_delta_path)

      expect(UploadFile, :download_file, fn ^source -> {:ok, source_url} end)
      expect(UploadFile, :download_file, fn ^target -> {:ok, target_url} end)

      expect(UpdateToolDefault, :create_firmware_delta_file, fn {_, ^source_url}, {_, ^target_url}, _ ->
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

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source.id, target.id)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, firmware_delta} =
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)

      assert firmware_delta.checksum == Firmwares.firmware_checksum(firmware_delta_path)
      assert firmware_delta.partials_checksums == [Firmwares.firmware_checksum(firmware_delta_path)]
    end

    test "creates a new firmware delta when one doesn't exist, and saves the checksum and partials checksums (multiple partials)",
         %{
           firmware: source,
           org_key: org_key,
           product: product,
           tmp_dir: tmp_dir
         } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"
      firmware_delta_path = Path.join(tmp_dir, "firmware_delta.fw")
      File.cp!("test/fixtures/fwup/dummy_4mb.txt", firmware_delta_path)

      expect(UploadFile, :download_file, fn ^source -> {:ok, source_url} end)
      expect(UploadFile, :download_file, fn ^target -> {:ok, target_url} end)

      expect(UpdateToolDefault, :create_firmware_delta_file, fn {_, ^source_url}, {_, ^target_url}, _ ->
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

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source.id, target.id)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, firmware_delta} =
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)

      assert firmware_delta.checksum == Firmwares.firmware_checksum(firmware_delta_path)
      assert firmware_delta.partials_checksums == Firmwares.partials_checksums(firmware_delta_path)
    end

    test "new firmware delta is not created if there is an error", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      expect(UpdateToolDefault, :create_firmware_delta_file, fn _s, _t, _wd ->
        {:ok,
         %{
           filepath: "test/fixtures/fwup/dummy_100kb.txt",
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
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)
    end

    test "update tool errors are handled", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      source_url = "http://somefilestore.com/source.fw"
      target_url = "http://somefilestore.com/target.fw"

      expect(UploadFile, :download_file, fn ^source -> {:ok, source_url} end)
      expect(UploadFile, :download_file, fn ^target -> {:ok, target_url} end)

      # Force error
      expect(UpdateToolDefault, :create_firmware_delta_file, fn {_, ^source_url}, {_, ^target_url}, _ ->
        {:error, :delta_not_created}
      end)

      assert {:ok, firmware_delta} = Firmwares.start_firmware_delta(source.id, target.id)
      Firmwares.generate_firmware_delta(firmware_delta, source, target)

      assert {:ok, _} =
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)
    end

    @tag :tmp_dir
    test "firmware deltas progress through status steps", %{
      firmware: %{id: source_id} = source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      %{id: target_id} = target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_delta_path = Path.join(tmp_dir, "firmware_delta.fw")
      File.cp!("test/fixtures/fwup/mixed.conf", firmware_delta_path)

      Firmwares.attempt_firmware_delta(source.id, target.id)
      delta = Repo.get_by!(FirmwareDelta, source_id: source.id, target_id: target.id)
      assert delta.status == :processing
      assert delta.tool == "pending"

      assert_enqueued(
        args: %{source_id: source_id, target_id: target_id},
        worker: FirmwareDeltaBuilder,
        queue: :firmware
      )

      expect(UpdateToolDefault, :create_firmware_delta_file, fn _, _, _ ->
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
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)
    end
  end

  describe "time_out_firmware_delta_generations/1" do
    test "time out old delta generations but not new ones", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      t1 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      t2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      t3 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      t4 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      old_time = DateTime.utc_now() |> DateTime.add(-2, :second)

      {:ok, %{id: d1}} = Firmwares.start_firmware_delta(source.id, t1.id)
      {:ok, %{id: d2}} = Firmwares.start_firmware_delta(source.id, t2.id)

      Repo.update_all(
        from(fd in FirmwareDelta, where: fd.id in [^d1, ^d2]),
        set: [inserted_at: old_time]
      )

      {:ok, %{id: d3}} = Firmwares.start_firmware_delta(source.id, t3.id)
      {:ok, %{id: d4}} = Firmwares.start_firmware_delta(source.id, t4.id)
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

    test "accepts a non-default sort", %{firmware: firmware, product: product} do
      {[result], _} = Firmwares.filter(product, %{sort: "uuid", sort_direction: "asc"})
      assert result.id == firmware.id
    end
  end

  describe "attempt_firmware_delta/2" do
    test "it doesn't start delta worker if delta exists", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      %FirmwareDelta{} = Fixtures.firmware_delta_fixture(source, target)

      {:ok, :delta_already_exists} = Firmwares.attempt_firmware_delta(source.id, target.id)
    end

    # Nothing to record when nothing was attempted. A started-then-failed delta
    # reads in the UI as "Deltas failed to generate", and -- worse -- leaves the
    # deployment group in `:deltas_failed`, where the orchestrator refuses to
    # send anything at all. A whole group would stop receiving updates because
    # of a patch that was never possible.
    test "it records nothing for a format that cannot be patched", %{
      firmware: source,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      stub(UpdateToolDefault, :supports_deltas?, fn -> false end)

      assert {:ok, :no_delta_support} = Firmwares.attempt_firmware_delta(source.id, target.id)

      assert {:error, :not_found} =
               Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)

      assert [] = all_enqueued(worker: FirmwareDeltaBuilder)
    end
  end

  describe "get_firmwares_by_product_and_platform/2" do
    test "returns firmwares matching product and platform", %{product: product, firmware: firmware} do
      result = Firmwares.get_firmwares_by_product_and_platform(product, firmware.platform)

      assert length(result) == 1
      assert hd(result).id == firmware.id
    end

    test "returns empty list for non-matching platform", %{product: product} do
      assert [] == Firmwares.get_firmwares_by_product_and_platform(product, "nonexistent")
    end

    test "does not return firmwares from other products", %{firmware: firmware, user: user, org: org} do
      other_product = Fixtures.product_fixture(user, org, %{name: "OtherProduct"})

      assert [] == Firmwares.get_firmwares_by_product_and_platform(other_product, firmware.platform)
    end
  end

  describe "get_delta_or_firmware/2" do
    test "returns completed delta when deployment_group and firmware are delta_updatable and delta exists", %{
      firmware: source,
      matching_device: device,
      org_key: org_key,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      # Enable delta_updatable on the target firmware
      Ecto.Changeset.change(target, delta_updatable: true) |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(target, %{user: user, delta_updatable: true})

      # Set device's firmware UUID to point to the source firmware.
      # fwup_version must be >= the delta's tool_metadata["delta_fwup_version"] (1.13.0)
      # for device_update_type/2 to return :delta.
      source_meta = %{
        uuid: source.uuid,
        architecture: source.architecture,
        platform: source.platform,
        product: product.name,
        version: source.version,
        fwup_version: "2.0.0"
      }

      {:ok, device} =
        NervesHub.Devices.update_firmware_metadata(device, source_meta, :unknown, false)

      firmware_delta = Fixtures.firmware_delta_fixture(source, target, %{status: :completed})

      {:ok, deployment_group} = NervesHub.ManagedDeployments.get_deployment_group(deployment_group)

      assert {:ok, result} = Firmwares.get_delta_or_firmware(device, deployment_group)
      assert result.id == firmware_delta.id
    end

    test "falls through to target firmware when delta status is not completed", %{
      firmware: source,
      matching_device: device,
      org_key: org_key,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      Ecto.Changeset.change(target, delta_updatable: true) |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(target, %{user: user, delta_updatable: true})

      source_meta = %{
        uuid: source.uuid,
        architecture: source.architecture,
        platform: source.platform,
        product: product.name,
        version: source.version
      }

      {:ok, device} =
        NervesHub.Devices.update_firmware_metadata(device, source_meta, :unknown, false)

      # Create a non-completed delta (processing)
      Fixtures.firmware_delta_fixture(source, target, %{status: :processing, tool: "pending"})

      {:ok, deployment_group} = NervesHub.ManagedDeployments.get_deployment_group(deployment_group)

      assert {:ok, result} = Firmwares.get_delta_or_firmware(device, deployment_group)
      assert result.id == target.id
    end

    test "returns target firmware when source UUID not in DB", %{
      matching_device: device,
      org_key: org_key,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      Ecto.Changeset.change(target, delta_updatable: true) |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(target, %{user: user, delta_updatable: true})

      # Device's firmware UUID points to nothing in DB
      device = Map.update!(device, :firmware_metadata, &%{&1 | uuid: Ecto.UUID.generate()})

      {:ok, deployment_group} = NervesHub.ManagedDeployments.get_deployment_group(deployment_group)

      assert {:ok, result} = Firmwares.get_delta_or_firmware(device, deployment_group)
      assert result.id == target.id
    end

    test "returns target firmware when deployment_group delta_updatable is false", %{
      matching_device: device,
      org_key: org_key,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      target = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      Ecto.Changeset.change(target, delta_updatable: true) |> Repo.update!()

      deployment_group =
        Fixtures.deployment_group_fixture(target, %{user: user, delta_updatable: false})

      {:ok, deployment_group} = NervesHub.ManagedDeployments.get_deployment_group(deployment_group)

      assert {:ok, result} = Firmwares.get_delta_or_firmware(device, deployment_group)
      assert result.id == target.id
    end
  end

  describe "metadata_from_device/2" do
    test "returns {:ok, metadata} when all required fields are present", %{
      product: product
    } do
      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_platform" => "test_host",
        "nerves_fw_product" => product.name,
        "nerves_fw_version" => "1.0.0"
      }

      assert {:ok, meta} = Firmwares.metadata_from_device(params, product.id)
      assert meta.uuid == params["nerves_fw_uuid"]
      assert meta.architecture == "arm64"
    end

    test "returns {:ok, nil} when UUID is missing entirely", %{product: product} do
      params = %{
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_platform" => "test_host",
        "nerves_fw_product" => product.name,
        "nerves_fw_version" => "1.0.0"
      }

      assert {:ok, nil} = Firmwares.metadata_from_device(params, product.id)
    end

    test "returns {:ok, nil} when UUID is present but not in DB", %{product: product} do
      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_platform" => "test_host",
        "nerves_fw_product" => product.name
        # missing version — makes changeset invalid
      }

      assert {:ok, nil} = Firmwares.metadata_from_device(params, product.id)
    end

    test "looks up DB firmware when changeset invalid but UUID is known", %{
      firmware: firmware,
      product: product
    } do
      params = %{
        "nerves_fw_uuid" => firmware.uuid,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_platform" => "test_host",
        "nerves_fw_product" => product.name
        # missing version — makes changeset invalid
      }

      assert {:ok, meta} = Firmwares.metadata_from_device(params, product.id)
      assert meta.uuid == firmware.uuid
    end
  end

  defp get_deltas_by_source_firmware(firmware) do
    FirmwareDelta
    |> where([fd], fd.source_id == ^firmware.id)
    |> Repo.all()
  end
end
