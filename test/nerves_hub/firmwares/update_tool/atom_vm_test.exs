defmodule NervesHub.Firmwares.UpdateTool.AtomVMTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool.AtomVM
  alias NervesHub.Firmwares.UpdateTool.Metadata
  alias NervesHub.Support.AtomVM, as: Builder

  defp write!(binary) do
    path = Path.join(System.tmp_dir!(), "atom_vm_#{System.unique_integer([:positive])}.avm")
    File.write!(path, binary)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "recognises?/1" do
    test "an archive carrying the magic" do
      assert AtomVM.recognises?(write!(Builder.packbeam()))
    end

    test "anything else, without reading past the header" do
      refute AtomVM.recognises?(write!(:binary.copy(<<0xE9>>, 4096)))
      refute AtomVM.recognises?(write!(""))
      refute AtomVM.recognises?(write!("#!/usr/bin/env"))
      refute AtomVM.recognises?(write!(<<"#!/usr/bin/env AtomVM\n", 1, 1>>))
    end

    test "a path that is not a file" do
      refute AtomVM.recognises?(Path.join(System.tmp_dir!(), "does-not-exist.avm"))
    end
  end

  describe "entries/1" do
    test "walks every entry in file order and stops at the terminator" do
      binary = Builder.packbeam(product: "blinky", modules: ["blinky", "blinky_worker"])

      assert {:ok, entries} = AtomVM.entries(binary)

      assert Enum.map(entries, & &1.name) == [
               "blinky.beam",
               "blinky_worker.beam",
               "blinky/priv/application.bin"
             ]

      assert Enum.map(entries, & &1.flags) == [0x02, 0x02, 0x04]
    end

    test "rejects a file without the magic" do
      assert {:error, :not_a_packbeam} = AtomVM.entries(:binary.copy(<<0>>, 64))
    end

    test "rejects an archive truncated mid entry" do
      binary = Builder.packbeam()
      truncated = binary_part(binary, 0, byte_size(binary) - 40)

      assert {:error, :truncated_packbeam} = AtomVM.entries(truncated)
    end

    test "rejects an entry whose size cannot hold its own header" do
      binary = Builder.magic() <> <<4::32, 2::32, 0::32>> <> Builder.terminator()

      assert {:error, :malformed_packbeam_entry} = AtomVM.entries(binary)
    end

    test "never raises on arbitrary bytes" do
      for _ <- 1..200 do
        bytes = :crypto.strong_rand_bytes(:rand.uniform(256))

        assert elem(AtomVM.entries(Builder.magic() <> bytes), 0) in [:ok, :error]
      end
    end
  end

  describe "get_firmware_metadata_from_file/1" do
    test "reads the application name, version and description" do
      path =
        write!(
          Builder.packbeam(
            product: "blinky",
            version: "2.3.4",
            description: "blinks an LED"
          )
        )

      assert {:ok, %{firmware_metadata: %Metadata{} = metadata, tool: "atomvm"}} =
               AtomVM.get_firmware_metadata_from_file(path)

      assert metadata.product == "blinky"
      assert metadata.version == "2.3.4"
      assert metadata.description == "blinks an LED"
    end

    test "describes the runtime rather than the silicon" do
      path = write!(Builder.packbeam())

      assert {:ok, %{firmware_metadata: metadata}} = AtomVM.get_firmware_metadata_from_file(path)

      assert metadata.platform == "atomvm"
      assert metadata.architecture == "beam"
    end

    test "derives the uuid from the archive, so identical bytes are one firmware" do
      binary = Builder.packbeam(product: "blinky", version: "1.0.0")
      other = Builder.packbeam(product: "blinky", version: "1.0.1")

      {:ok, %{firmware_metadata: first}} = AtomVM.get_firmware_metadata_from_file(write!(binary))
      {:ok, %{firmware_metadata: same}} = AtomVM.get_firmware_metadata_from_file(write!(binary))
      {:ok, %{firmware_metadata: different}} = AtomVM.get_firmware_metadata_from_file(write!(other))

      assert first.uuid == same.uuid
      refute first.uuid == different.uuid
      assert first.uuid =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end

    test "records the digest and the raw vsn as tool metadata" do
      binary = Builder.packbeam(version: "1.2")
      path = write!(binary)

      assert {:ok, %{tool_metadata: tool_metadata}} = AtomVM.get_firmware_metadata_from_file(path)

      assert tool_metadata["avm_sha256"] == Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
      assert tool_metadata["application_vsn_raw"] == "1.2"
      assert tool_metadata["packbeam_size"] == byte_size(binary)
      assert tool_metadata["module_count"] == 1
    end

    # `atomvm_packbeam` writes the project's own application ahead of the
    # dependency archives it appends, and nothing in the file marks which is the
    # root, so first wins.
    test "takes the first application spec, which is the project's own" do
      path =
        write!(
          Builder.packbeam(
            product: "blinky",
            version: "3.0.0",
            applications: [{"atomvm_lib", "0.1.0"}, {"gpio", "0.2.0"}]
          )
        )

      assert {:ok, %{firmware_metadata: metadata}} = AtomVM.get_firmware_metadata_from_file(path)

      assert metadata.product == "blinky"
      assert metadata.version == "3.0.0"
    end

    test "rejects an archive with no application metadata" do
      binary = Builder.magic() <> Builder.entry("blinky.beam", 0x02, "code") <> Builder.terminator()

      assert {:error, :no_application_metadata} = AtomVM.get_firmware_metadata_from_file(write!(binary))
    end

    test "rejects an unreadable application spec rather than raising" do
      binary =
        Builder.magic() <>
          Builder.entry("blinky/priv/application.bin", 0x04, <<8::32, 131, 0xFF, 0xFF, 0xFF>>) <>
          Builder.terminator()

      assert {:error, :malformed_application_metadata} = AtomVM.get_firmware_metadata_from_file(write!(binary))
    end
  end

  # Reading an uploaded archive with `:erlang.binary_to_term/2` would intern an
  # atom for every atom in the term, and atoms are never collected. `:safe` is
  # no help, since the application name is exactly the atom the server has never
  # seen.
  describe "term decoding" do
    # Asserted on the specific atoms rather than on `:erlang.system_info(:atom_count)`,
    # which is global and moves under any other test running alongside this one.
    test "reading an archive does not add to the atom table" do
      name = "zzz_app_#{System.unique_integer([:positive])}"
      description = "zzz_description_#{System.unique_integer([:positive])}"
      path = write!(Builder.packbeam(product: name, description: description))

      assert {:ok, %{firmware_metadata: metadata}} = AtomVM.get_firmware_metadata_from_file(path)
      assert metadata.product == name
      assert metadata.description == description

      # Every atom the term carried, including the ones the decoder had to read
      # to find its way to the version.
      for never_an_atom <- [name, description] do
        assert_raise ArgumentError, fn -> String.to_existing_atom(never_an_atom) end
      end
    end

    test "decodes the shapes an application spec is built from" do
      assert {:ok, {"application", "blinky", properties}, ""} =
               AtomVM.decode_term(
                 <<131, 104, 3, 119, 11, "application", 119, 6, "blinky", 108, 2::32, 104, 2, 119, 3, "vsn", 107, 5::16,
                   "1.0.0", 104, 2, 119, 8, "included", 106, 106>>
               )

      assert properties == [{"vsn", "1.0.0"}, {"included", []}]
    end

    test "refuses a term it does not understand rather than guessing" do
      assert :error = AtomVM.decode_term(<<131, 70, 0::64>>)
      assert :error = AtomVM.decode_term(<<0, 1, 2>>)
    end
  end

  describe "normalise_version/1" do
    test "accepts semver as it stands" do
      assert {:ok, "1.2.3"} = AtomVM.normalise_version("1.2.3")
      assert {:ok, "1.2.3-rc.1"} = AtomVM.normalise_version("1.2.3-rc.1")
      assert {:ok, "1.2.3+build.5"} = AtomVM.normalise_version("1.2.3+build.5")
    end

    test "accepts a leading v and a two part version" do
      assert {:ok, "1.2.3"} = AtomVM.normalise_version("v1.2.3")
      assert {:ok, "1.2.0"} = AtomVM.normalise_version("1.2")
      assert {:ok, "1.2.0"} = AtomVM.normalise_version("v1.2")
      assert {:ok, "1.2.3"} = AtomVM.normalise_version("  1.2.3  ")
    end

    test "rejects what it cannot read, rather than coercing it" do
      assert {:error, {:invalid_version, "git"}} = AtomVM.normalise_version("git")
      assert {:error, {:invalid_version, "1"}} = AtomVM.normalise_version("1")
      assert {:error, {:invalid_version, "1.2.3.4"}} = AtomVM.normalise_version("1.2.3.4")
      assert {:error, {:invalid_version, ""}} = AtomVM.normalise_version("")
    end

    test "an archive whose vsn is unreadable is refused" do
      path = write!(Builder.packbeam(version: "not-a-version"))

      assert {:error, {:invalid_version, "not-a-version"}} = AtomVM.get_firmware_metadata_from_file(path)
    end
  end

  describe "signatures" do
    # Nothing signs a packbeam today, so an archive is legitimately unsigned
    # rather than failing verification.
    test "every archive verifies as unsigned" do
      assert {:ok, nil} = AtomVM.verify_signature(write!(Builder.packbeam()), [])
    end
  end

  describe "deltas" do
    test "the format cannot be patched, so none are generated" do
      refute AtomVM.supports_deltas?()
      refute AtomVM.delta_updatable?(%{})
      assert AtomVM.device_update_type(%Device{}, %Firmware{}) == :full
    end

    test "creating one is refused rather than producing something unusable" do
      assert {:error, :deltas_not_supported} =
               AtomVM.create_firmware_delta_file({"a", "http://a"}, {"b", "http://b"}, "/tmp")
    end

    test "cleanup is a no-op" do
      assert :ok = AtomVM.cleanup_firmware_delta_files("/tmp/nothing")
    end
  end

  describe "device metadata" do
    test "recognises what an AtomVM device reports" do
      assert AtomVM.recognises_device_metadata?(%{"atomvm_app_name" => "blinky"})
      assert AtomVM.recognises_device_metadata?(%{"atomvm_avm_sha256" => "ab"})
      refute AtomVM.recognises_device_metadata?(%{"nerves_fw_uuid" => "x"})
      refute AtomVM.recognises_device_metadata?(%{"esp_idf_project_name" => "x"})
    end

    test "carries the VM version, which no archive can know" do
      metadata =
        AtomVM.metadata_from_device(%{
          "atomvm_app_name" => "blinky",
          "atomvm_app_version" => "1.2",
          "atomvm_version" => "0.6.5"
        })

      assert metadata.product == "blinky"
      assert metadata.version == "1.2.0"
      assert metadata.description == "AtomVM 0.6.5"
      assert metadata.platform == "atomvm"
      assert metadata.architecture == "beam"
    end

    # The device sends a hash, not a UUID: the mapping is this module's
    # convention and lives in one place so a device agent cannot get it wrong.
    test "derives the same uuid from a device's hash as from the archive" do
      binary = Builder.packbeam(product: "blinky")
      digest = :crypto.hash(:sha256, binary)

      {:ok, %{firmware_metadata: from_file}} = AtomVM.get_firmware_metadata_from_file(write!(binary))

      from_device =
        AtomVM.metadata_from_device(%{
          "atomvm_app_name" => "blinky",
          "atomvm_avm_sha256" => Base.encode16(digest, case: :lower)
        })

      assert from_device.uuid == from_file.uuid
    end

    test "a device reporting nothing usable yields nils rather than raising" do
      metadata = AtomVM.metadata_from_device(%{"atomvm_app_name" => "blinky"})

      assert metadata.uuid == nil
      assert metadata.version == nil
      assert metadata.description == nil
    end

    test "an unreadable hash or version costs only that field" do
      metadata =
        AtomVM.metadata_from_device(%{
          "atomvm_app_name" => "blinky",
          "atomvm_app_version" => "git",
          "atomvm_avm_sha256" => "not-hex"
        })

      assert metadata.product == "blinky"
      assert metadata.uuid == nil
      assert metadata.version == nil
    end
  end
end
