defmodule NervesHubCore.Support.Fwup do
  @moduledoc """
  This module is intended to help with testing and development
  by allowing for "easy" creation of firmware signing keys, and
  signed/unsigned/corrupted firmware files.

  It is a thin wrapper around `fwup`, and it persists the files in
  `System.tmp_dir()`.
  """
  defmodule MetaParams do
    defstruct product: "nerves-hub",
              description: "D",
              version: "1.0.0",
              platform: "platform",
              architecture: "x86_64",
              author: "me"
  end

  defp conf_file() do
    Path.join([System.tmp_dir(), "test-fwup.conf"])
  end

  defp build_conf_contents(%MetaParams{} = meta_params) do
    """
    meta-product = "#{meta_params.product}"
    meta-description = "#{meta_params.description} "
    meta-version = "#{meta_params.version}"
    meta-platform = "#{meta_params.platform}"
    meta-architecture = "#{meta_params.architecture}"
    meta-author = "#{meta_params.author}"

    file-resource  #{Ecto.UUID.generate()}.txt {
    contents = "Hello, world!"
    }
    """
  end

  defp make_conf(%MetaParams{} = meta_params) do
    File.rm(conf_file())
    File.write!(conf_file(), build_conf_contents(meta_params))
  end

  def gen_key_pair(key_name) do
    key_path_no_extension = Path.join([System.tmp_dir(), key_name])

    for ext <- ~w(.priv .pub) do
      File.rm(key_path_no_extension <> ext)
    end

    System.cmd("fwup", ["-g", "-o", key_path_no_extension])
  end

  def get_public_key(key_name) do
    File.read!(Path.join([System.tmp_dir(), key_name <> ".pub"]))
  end

  def create_firmware(firmware_name, meta_params \\ %{}) do
    make_conf(struct(MetaParams, meta_params))
    out_path = Path.join([System.tmp_dir(), firmware_name <> ".fw"])
    File.rm(out_path)

    System.cmd("fwup", [
      "-c",
      "-f",
      conf_file(),
      "-o",
      out_path
    ])

    {:ok, out_path}
  end

  def sign_firmware(key_name, firmware_name, output_name) do
    dir = System.tmp_dir()
    output_path = Path.join([dir, output_name <> ".fw"])

    System.cmd("fwup", [
      "-S",
      "-s",
      Path.join([dir, key_name <> ".priv"]),
      "-i",
      Path.join([dir, firmware_name <> ".fw"]),
      "-o",
      output_path
    ])

    {:ok, output_path}
  end

  def create_signed_firmware(key_name, firmware_name, output_name, meta_params \\ %{}) do
    create_firmware(firmware_name, meta_params)
    sign_firmware(key_name, firmware_name, output_name)
  end

  def corrupt_firmware_file(input_path, output_name \\ "corrupt") do
    output_path = Path.join([System.tmp_dir(), output_name <> ".fw"])
    System.cmd("dd", ["if=" <> input_path, "of=" <> output_path, "bs=512", "count=1"])

    {:ok, output_path}
  end
end
