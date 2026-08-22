defmodule NervesHub.Firmwares.UpdateTool.EspIdfTest do
  use ExUnit.Case, async: true

  alias NervesHub.Firmwares.UpdateTool.EspIdf
  alias NervesHub.Firmwares.UpdateTool.Metadata

  @elf_sha256 :binary.copy(<<0xAB>>, 32)

  # Builds the first 0x120 bytes of an ESP-IDF application image: a 24 byte
  # esp_image_header_t, an 8 byte esp_image_segment_header_t, then the 256 byte
  # esp_app_desc_t at offset 0x20.
  defp image(opts \\ []) do
    chip_id = Keyword.get(opts, :chip_id, 0x0009)
    version = Keyword.get(opts, :version, "1.2.3")
    project_name = Keyword.get(opts, :project_name, "my_app")
    idf_ver = Keyword.get(opts, :idf_ver, "v5.2.1")
    elf_sha256 = Keyword.get(opts, :elf_sha256, @elf_sha256)

    image_header =
      <<0xE9, 3::8, 2::8, 0x2F::8, 0x40080000::little-32, 0xEE::8, 0, 0, 0, chip_id::little-16, 0::8, 0::little-16,
        0xFFFF::little-16, 0, 0, 0, 0, 0::8>>

    segment_header = <<0x3F400020::little-32, 1024::little-32>>

    app_desc =
      <<0xABCD5432::little-32, 0::little-32, 0::little-64>> <>
        pad(version, 32) <>
        pad(project_name, 32) <>
        pad("12:34:56", 16) <>
        pad("Jan  1 2026", 16) <>
        pad(idf_ver, 32) <>
        elf_sha256 <>
        :binary.copy(<<0>>, 80)

    24 = byte_size(image_header)
    8 = byte_size(segment_header)
    256 = byte_size(app_desc)

    image_header <> segment_header <> app_desc
  end

  defp pad(string, size), do: string <> :binary.copy(<<0>>, size - byte_size(string))

  defp write!(binary) do
    path = Path.join(System.tmp_dir!(), "esp_idf_#{System.unique_integer([:positive])}.bin")
    File.write!(path, binary)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "create_firmware_delta_file/3" do
    setup do
      if !System.find_executable("detools") do
        raise """
        `detools` is not installed, and the ESP-IDF delta tests need it.

            pip install detools
        """
      end

      :ok
    end

    # Two images that share most of their bytes, which is what two builds of one
    # application look like. Padded well past the header so the patch has
    # something to be smaller than.
    defp delta_pair() do
      shared = :crypto.strong_rand_bytes(200_000)

      source = image(version: "1.2.3") <> shared <> :binary.copy(<<0x11>>, 4_000)
      target = image(version: "1.2.4") <> shared <> :binary.copy(<<0x22>>, 4_000)

      {source, target}
    end

    defp serve!(%{"source.bin" => source, "target.bin" => target}) do
      Req.Test.stub(NervesHub, fn conn ->
        body = if String.ends_with?(conn.request_path, "source.bin"), do: source, else: target

        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.send_resp(200, body)
      end)
    end

    @tag :tmp_dir
    test "produces a patch far smaller than the image it rebuilds", %{tmp_dir: tmp_dir} do
      {source, target} = delta_pair()
      serve!(%{"source.bin" => source, "target.bin" => target})

      assert {:ok, delta} =
               EspIdf.create_firmware_delta_file(
                 {"source-uuid", "http://example.test/source.bin"},
                 {"target-uuid", "http://example.test/target.bin"},
                 tmp_dir
               )

      assert delta.tool == "esp-idf"
      assert delta.source_size == byte_size(source)
      assert delta.target_size == byte_size(target)
      assert delta.size < delta.target_size
      assert File.exists?(delta.filepath)
    end

    # The device decodes exactly these, and a detools default that moved in a
    # later release would move the format under devices already in the field.
    @tag :tmp_dir
    test "records the format the device has to decode", %{tmp_dir: tmp_dir} do
      {source, target} = delta_pair()
      serve!(%{"source.bin" => source, "target.bin" => target})

      assert {:ok, delta} =
               EspIdf.create_firmware_delta_file(
                 {"source-uuid", "http://example.test/source.bin"},
                 {"target-uuid", "http://example.test/target.bin"},
                 tmp_dir
               )

      assert delta.tool_metadata == %{
               "patch_format" => "detools",
               "compression" => "heatshrink",
               "patch_type" => "sequential",
               "algorithm" => "bsdiff"
             }
    end

    # The property everything else rests on. A Secure Boot signature travels
    # inside the image, so a device that rebuilds the target from a patch is
    # verifying the signature over bytes it reconstructed -- which only works if
    # the reconstruction is exact. Nothing is re-signed on the device.
    @tag :tmp_dir
    test "the patch rebuilds the target byte for byte", %{tmp_dir: tmp_dir} do
      {source, target} = delta_pair()
      serve!(%{"source.bin" => source, "target.bin" => target})

      assert {:ok, delta} =
               EspIdf.create_firmware_delta_file(
                 {"source-uuid", "http://example.test/source.bin"},
                 {"target-uuid", "http://example.test/target.bin"},
                 tmp_dir
               )

      source_path = Path.join(tmp_dir, "rebuild_source.bin")
      rebuilt_path = Path.join(tmp_dir, "rebuilt.bin")
      File.write!(source_path, source)

      assert {_, 0} =
               System.cmd("detools", ["apply_patch", source_path, delta.filepath, rebuilt_path],
                 stderr_to_stdout: true,
                 env: []
               )

      assert File.read!(rebuilt_path) == target
    end

    # A worker that crashes is a worker that retries and crashes again. A tool
    # that is not installed has to read as a failed delta.
    @tag :tmp_dir
    test "a download failure is reported rather than raised", %{tmp_dir: tmp_dir} do
      Req.Test.stub(NervesHub, fn conn -> Plug.Conn.send_resp(conn, 404, "nope") end)

      assert {:error, _} =
               EspIdf.create_firmware_delta_file(
                 {"source-uuid", "http://example.test/source.bin"},
                 {"target-uuid", "http://example.test/target.bin"},
                 tmp_dir
               )
    end
  end

  describe "recognises?/1" do
    test "accepts an image carrying both magic numbers" do
      assert EspIdf.recognises?(write!(image()))
    end

    test "rejects a file with the image magic but no app descriptor" do
      refute EspIdf.recognises?(write!(<<0xE9>> <> :binary.copy(<<0>>, 512)))
    end

    test "rejects an fwup archive" do
      refute EspIdf.recognises?(write!("PK" <> <<0x03, 0x04>> <> :binary.copy(<<0>>, 512)))
    end

    test "rejects a file shorter than the headers without raising" do
      refute EspIdf.recognises?(write!(<<0xE9, 0, 0>>))
    end
  end

  describe "get_firmware_metadata_from_file/1" do
    test "maps the descriptor onto firmware metadata" do
      path = write!(image(chip_id: 0x0009, version: "1.2.3", project_name: "my_app"))

      assert {:ok, %{firmware_metadata: %Metadata{} = meta, tool: "esp-idf", tool_metadata: tool_meta}} =
               EspIdf.get_firmware_metadata_from_file(path)

      assert meta.product == "my_app"
      assert meta.version == "1.2.3"
      assert meta.platform == "esp32s3"
      assert meta.architecture == "xtensa"
      assert meta.description == "ESP-IDF v5.2.1"
      # First 16 bytes of app_elf_sha256, formatted as a UUID.
      assert meta.uuid == "abababab-abab-abab-abab-abababababab"

      assert tool_meta["idf_ver"] == "v5.2.1"
      assert tool_meta["chip_id"] == 0x0009
      assert tool_meta["app_elf_sha256"] == String.duplicate("ab", 32)
    end

    test "derives a stable uuid from the elf hash" do
      a = write!(image(elf_sha256: :binary.copy(<<0x11>>, 32)))
      b = write!(image(elf_sha256: :binary.copy(<<0x22>>, 32)))

      {:ok, %{firmware_metadata: meta_a}} = EspIdf.get_firmware_metadata_from_file(a)
      {:ok, %{firmware_metadata: meta_b}} = EspIdf.get_firmware_metadata_from_file(b)

      assert meta_a.uuid != meta_b.uuid
      assert {:ok, %{firmware_metadata: ^meta_a}} = EspIdf.get_firmware_metadata_from_file(a)
    end

    test "maps riscv chips" do
      path = write!(image(chip_id: 0x000D))
      {:ok, %{firmware_metadata: meta}} = EspIdf.get_firmware_metadata_from_file(path)
      assert meta.platform == "esp32c6"
      assert meta.architecture == "riscv"
    end

    test "carries an unknown chip id through rather than failing" do
      path = write!(image(chip_id: 0x00FE))
      {:ok, %{firmware_metadata: meta}} = EspIdf.get_firmware_metadata_from_file(path)
      assert meta.platform == "esp32-254"
      assert meta.architecture == "unknown"
    end

    test "rejects a version PROJECT_VER could not have meant" do
      path = write!(image(version: "not-a-version"))

      assert {:error, {:invalid_version, "not-a-version"}} =
               EspIdf.get_firmware_metadata_from_file(path)
    end
  end

  describe "normalise_version/1" do
    test "passes through valid semver" do
      assert {:ok, "1.2.3"} = EspIdf.normalise_version("1.2.3")
      assert {:ok, "1.2.3-rc.1"} = EspIdf.normalise_version("1.2.3-rc.1")
    end

    test "strips a leading v, as git describe emits" do
      assert {:ok, "1.2.3"} = EspIdf.normalise_version("v1.2.3")
    end

    test "pads short versions" do
      assert {:ok, "1.0.0"} = EspIdf.normalise_version("1")
      assert {:ok, "1.2.0"} = EspIdf.normalise_version("1.2")
    end

    test "moves ESP's fourth component into build metadata" do
      assert {:ok, "0.1.0+1"} = EspIdf.normalise_version("0.1.0.1")
    end

    test "keeps git describe suffixes, which are already valid semver prereleases" do
      assert {:ok, "1.2.3-4-gabcdef"} = EspIdf.normalise_version("v1.2.3-4-gabcdef")
    end

    test "rejects anything else rather than guessing" do
      assert {:error, {:invalid_version, "banana"}} = EspIdf.normalise_version("banana")
      assert {:error, {:invalid_version, ""}} = EspIdf.normalise_version("")
    end
  end

  describe "verify_signature/2" do
    test "refuses an image with no signature block" do
      assert {:error, :firmware_not_signed} = EspIdf.verify_signature(write!(image()), [])
    end

    # Signature verification against a real espsecure.py-signed image, including
    # the offset regression this file used to cover with a hand-rolled signer,
    # lives in `EspIdfSignatureTest`.
  end
end
