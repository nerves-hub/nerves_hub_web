defmodule NervesHub.Support.EspIdf do
  @moduledoc """
  Builds synthetic ESP-IDF application images for tests.

  The real thing is produced by `idf.py build` and is megabytes of compiled
  code, but everything NervesHub reads sits in the first 0x120 bytes — a 24 byte
  `esp_image_header_t`, an 8 byte `esp_image_segment_header_t`, and the 256 byte
  `esp_app_desc_t` at offset 0x20. So a test image is those headers followed by
  filler, and it exercises exactly the same parsing path as a real build.

  This mirrors `NervesHub.Support.Fwup` in intent: it lets a test produce an
  uploadable firmware file without a toolchain.
  """

  @doc """
  Build an ESP-IDF application image as a binary.

  ## Options

    * `:product` — `PROJECT_NAME`, must match a NervesHub product to upload
    * `:version` — `PROJECT_VER`, defaults to `"1.0.0"`
    * `:chip_id` — `esp_chip_id_t`, defaults to `0x0009` (ESP32-S3)
    * `:idf_ver` — the IDF version string
    * `:elf_sha256` — 32 bytes; NervesHub derives the firmware UUID from this,
      so it defaults to random bytes to keep separate images distinct
    * `:padding` — bytes of filler appended after the headers
  """
  @spec image(keyword()) :: binary()
  def image(opts \\ []) do
    chip_id = Keyword.get(opts, :chip_id, 0x0009)
    version = Keyword.get(opts, :version, "1.0.0")
    product = Keyword.get(opts, :product, "nerves-hub")
    idf_ver = Keyword.get(opts, :idf_ver, "v5.2.1")
    elf_sha256 = Keyword.get(opts, :elf_sha256, :crypto.strong_rand_bytes(32))
    padding = Keyword.get(opts, :padding, 1024)

    image_header(chip_id) <>
      segment_header() <>
      app_desc(version, product, idf_ver, elf_sha256) <>
      :binary.copy(<<0>>, padding)
  end

  @sector 4096

  @doc """
  Sign an image the way `espsecure.py sign_data --version 2` does.

  Pads the image to a 4 KB boundary, then appends a 4 KB sector whose first
  1216 bytes are the RSA-3072 signature block.

  The ground truth for the block's layout is `EspIdfSignatureTest`, which
  verifies an image signed by the actual `espsecure.py` and committed under
  `test/fixtures/esp_idf/`. This signer exists so that other suites can vary
  product name and version without shelling out to Python — check any change to
  it against that test, which cannot share a mistake with it.
  """
  @spec signed_image(keyword()) :: binary()
  def signed_image(opts \\ []) do
    image = image(opts)
    padded = image <> :binary.copy(<<0>>, pad_to(byte_size(image), @sector))
    digest = :crypto.hash(:sha256, padded)

    padded <> signature_sector(digest)
  end

  @doc """
  The PEM public key matching `signed_image/1`, for registering as an org key.
  """
  @spec signing_public_key() :: String.t()
  def signing_public_key(), do: File.read!("test/fixtures/esp_idf/signing_key_public.pem")

  defp signature_sector(digest) do
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = private_key()

    signature =
      :public_key.sign(
        {:digest, digest},
        :sha256,
        private_key(),
        [{:rsa_padding, :rsa_pkcs1_pss_padding}, {:rsa_pss_saltlen, 32}, {:rsa_mgf1_md, :sha256}]
      )

    # Stored little-endian for the ESP32 RSA peripheral.
    block =
      <<0xE7, 0x02, 0, 0>> <>
        digest <>
        reverse(pad_int(modulus, 384)) <>
        <<exponent::little-32>> <>
        :binary.copy(<<0>>, 384) <>
        <<0::little-32>> <>
        reverse(signature)

    block = block <> <<:erlang.crc32(block)::little-32>>

    block <> :binary.copy(<<0>>, @sector - byte_size(block))
  end

  defp private_key() do
    "test/fixtures/esp_idf/signing_key_TEST_ONLY.pem"
    |> File.read!()
    |> :public_key.pem_decode()
    |> hd()
    |> :public_key.pem_entry_decode()
  end

  defp pad_int(int, bytes) do
    raw = :binary.encode_unsigned(int)
    :binary.copy(<<0>>, bytes - byte_size(raw)) <> raw
  end

  defp reverse(binary) do
    binary |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp pad_to(size, boundary) do
    case rem(size, boundary) do
      0 -> 0
      remainder -> boundary - remainder
    end
  end

  @doc """
  Write an image to `dir` and return its path.
  """
  @spec create_firmware(String.t(), keyword()) :: {:ok, String.t()}
  def create_firmware(product_name, opts \\ []) do
    dir = Keyword.get(opts, :dir, System.tmp_dir!())
    name = Keyword.get(opts, :name, "esp-idf-#{System.unique_integer([:positive])}")
    path = Path.join(dir, "#{name}.bin")

    opts = Keyword.put(opts, :product, product_name)

    contents =
      if Keyword.get(opts, :signed, true) do
        signed_image(opts)
      else
        image(opts)
      end

    File.write!(path, contents)

    {:ok, path}
  end

  # esp_image_header_t — 24 bytes, chip_id at offset 12.
  defp image_header(chip_id) do
    <<0xE9, 3::8, 2::8, 0x2F::8, 0x40080000::little-32, 0xEE::8, 0, 0, 0, chip_id::little-16, 0::8, 0::little-16,
      0xFFFF::little-16, 0, 0, 0, 0, 0::8>>
  end

  # esp_image_segment_header_t — 8 bytes.
  defp segment_header(), do: <<0x3F400020::little-32, 1024::little-32>>

  # esp_app_desc_t — 256 bytes, magic_word 0xABCD5432.
  defp app_desc(version, product, idf_ver, elf_sha256) do
    <<0xABCD5432::little-32, 0::little-32, 0::little-64>> <>
      pad(version, 32) <>
      pad(product, 32) <>
      pad("12:34:56", 16) <>
      pad("Jan  1 2026", 16) <>
      pad(idf_ver, 32) <>
      elf_sha256 <>
      :binary.copy(<<0>>, 80)
  end

  defp pad(string, size) when byte_size(string) < size do
    string <> :binary.copy(<<0>>, size - byte_size(string))
  end
end
