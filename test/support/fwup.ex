defmodule NervesHub.Support.Fwup do
  @moduledoc """
  This module is intended to help with testing and development
  by allowing for "easy" creation of firmware signing keys, and
  signed/unsigned/corrupted firmware files.

  It is a thin wrapper around `fwup`, and it persists the files in
  `System.tmp_dir()`.

  The files are given the names that are passed to the respective functions, so
  make sure you pass unique names to avoid collisions if necessary.  This module
  takes little effort to avoid collisions on its own.
  """

  defmodule MetaParams do
    defstruct product: "nerves-hub",
              description: "D",
              version: "1.0.0",
              platform: "platform",
              architecture: "x86_64",
              author: "me"
  end

  @doc """
  Generate a public/private key pair for firmware signing. The `key_name`
  argument can be used to lookup the public key via `get_public_key/1` or to
  specify the private key to be used for signing a firmware image via
  `sign_firmware/3` and `create_signed_firmware/4`
  """
  def gen_key_pair(key_name, dir \\ System.tmp_dir()) do
    key_path_no_extension = Path.join([dir, key_name])

    _ = System.cmd("fwup", ["-g", "-o", key_path_no_extension], stderr_to_stdout: true)

    :ok
  end

  @doc """
  Get a public key which has been generated via `gen_key_pair/1`.
  """
  def get_public_key(key_name, dir \\ System.tmp_dir()) do
    File.read!(Path.join([dir, key_name <> ".pub"]))
  end

  @doc """
  Create an unsigned firmware image, and return the path to that image.
  """
  def create_firmware(dir, firmware_name, meta_params \\ %{}) do
    conf_path = make_conf(struct(MetaParams, meta_params), dir)
    out_path = Path.join([dir, firmware_name <> ".fw"])

    {_, 0} =
      System.cmd("fwup", [
        "-c",
        "-f",
        conf_path,
        "-o",
        out_path
      ])

    {:ok, out_path}
  end

  @doc """
  Sign a firmware image, and return the path to that image. The `firmware_name`
  argument must match the name of a firmware created with `create_firmware/2`.
  """
  def sign_firmware(dir, key_name, firmware_name, output_name) do
    output_path = Path.join([dir, output_name <> ".fw"])

    {_, 0} =
      System.cmd(
        "fwup",
        [
          "-S",
          "-s",
          Path.join([dir, key_name <> ".priv"]),
          "-i",
          Path.join([dir, firmware_name <> ".fw"]),
          "-o",
          output_path
        ],
        stderr_to_stdout: true
      )

    {:ok, output_path}
  end

  @doc """
  Create a signed firmware image, and return the path to that image.
  """
  def create_signed_firmware(key_name, firmware_name, output_name, meta_params \\ %{}) do
    {dir, meta_params} = Map.pop(meta_params, :dir, System.tmp_dir())
    {:ok, _} = create_firmware(dir, firmware_name, meta_params)
    sign_firmware(dir, key_name, firmware_name, output_name)
  end

  @doc """
  Corrupt an existing firmware image.
  """
  def corrupt_firmware_file(input_path, dir \\ System.tmp_dir()) do
    output_path = Path.join([dir, "corrupt.fw"])

    {_, 0} =
      System.cmd("dd", ["if=" <> input_path, "of=" <> output_path, "bs=256", "count=1"],
        stderr_to_stdout: true
      )

    {:ok, output_path}
  end

  defp make_conf(%MetaParams{} = meta_params, dir) do
    path = Path.join([dir, "#{Ecto.UUID.generate()}.conf"])
    File.write!(path, build_conf_contents(meta_params))

    path
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
end
